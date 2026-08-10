// Derived from Gander (MIT), copyright (c) 2026 Arjun Maniyani.
package vn.bizreader.connect.viewer

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.View
import android.view.ViewGroup
import android.webkit.MimeTypeMap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.content.IntentCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import com.davemorrissey.labs.subscaleview.ImageSource
import com.davemorrissey.labs.subscaleview.SubsamplingScaleImageView
import com.google.android.material.appbar.MaterialToolbar
import vn.bizreader.connect.R
import vn.bizreader.connect.viewer.FileKind.Companion.detect
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class ViewerActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_PATH = "path"
        private const val ASSET_HOST = "appassets.androidplatform.net"
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
        private const val DOWNLOADS_AUTHORITY = "com.android.providers.downloads.documents"

        /**
         * Above this, a document is served in ranges rather than read whole.
         *
         * This is a memory threshold, not a speed one. Bulk and ranged loading were
         * measured against each other at 0.2, 2.7, 8, 16, 32 and 53 MB on a Nothing
         * Phone 2: below about 32 MB the difference had no consistent sign and stayed
         * inside run-to-run noise, and only at 53 MB did ranging win repeatably, by
         * around 80 ms. So anywhere in that band is equally defensible on speed, and
         * the number is chosen instead for what it avoids holding in memory. 16 MB is
         * comfortable to buffer on a low-end device; a 50 MB scan is not.
         */
        private const val RANGE_THRESHOLD_BYTES = 16L * 1024 * 1024

        /**
         * Chromium major version the vendored pdf.js needs. Mozilla puts the legacy
         * build's floor at Chrome 125, and `lib/pdf.min.mjs` is pdfjs-dist 5.7.284
         * legacy. Below it, `pdf.html` says so instead of loading the renderer.
         *
         * Read this before raising it alongside a pdf.js upgrade. Chromium 138 is the
         * last WebView that Android 8.0, 8.1 and 9.0 will ever receive, because 139
         * requires Android 10 and minSdk here is 26. A pdf.js release needing more than
         * 138 therefore does not degrade on API 26 to 28, it ends PDF support there for
         * good. docs/VENDORED.md carries the same warning next to the version fetched.
         */
        private const val PDFJS_MIN_CHROMIUM_MAJOR = 125

        /**
         * Below this, a parsed major is treated as unreadable rather than as ancient.
         * WebView only became updatable at Chromium 33, so a provider reporting
         * something like "1.0" is telling us it does not use Chromium version numbers,
         * not that it predates them, and refusing its PDFs would break a device that
         * works today.
         */
        private const val PLAUSIBLE_CHROMIUM_MAJOR = 30
    }

    private var webView: WebView? = null
    private var player: ExoPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_viewer)
        applySystemBarInsets(findViewById(R.id.root))

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        toolbar.setNavigationOnClickListener { finish() }
        val container = findViewById<FrameLayout>(R.id.container)

        // Files arrive via VIEW (data), the share sheet (EXTRA_STREAM),
        // a plain path extra, or as shared text (EXTRA_TEXT).
        val uri = intent.data
            ?: IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            ?: intent.getStringExtra(EXTRA_PATH)?.let { Uri.fromFile(File(it)) }
            ?: sharedTextUri()
        if (uri == null) {
            finish()
            return
        }

        val name = resolveDisplayName(uri)
        toolbar.title = name
        val ext = name.substringAfterLast('.', "").lowercase()
        val mime = runCatching { contentResolver.getType(uri) }.getOrNull() ?: intent.type

        // Held past the when because setUpSearch needs it to know whether the
        // format it is offering to search actually has anything findable in it
        val kind = detect(ext, mime)
        when (kind) {
            FileKind.IMAGE -> showImage(container, uri, name, ext)
            FileKind.PLAYER -> showPlayer(container, uri, name, ext)
            else -> showWeb(container, uri, kind, name, ext)
        }
        setUpSearch(toolbar, kind)
        setUpActions(toolbar, uri, ext, mime)
    }

    /** Share and "show in file manager" toolbar actions. */
    private fun setUpActions(toolbar: MaterialToolbar, uri: Uri, ext: String, mime: String?) {
        toolbar.menu.findItem(R.id.action_share).setOnMenuItemClickListener {
            shareFile(uri, ext, mime)
            true
        }
        val folder = containingFolder(uri)
        toolbar.menu.findItem(R.id.action_open_folder).apply {
            isVisible = folder != null
            setOnMenuItemClickListener {
                openFolder(folder ?: return@setOnMenuItemClickListener true)
                true
            }
        }
    }

    private fun shareFile(uri: Uri, ext: String, mime: String?) {
        // Received content:// URIs go out with a read grant passed along; our own
        // file:// URIs (the shared-text temp file) go through the FileProvider
        val shareUri =
            if (uri.scheme == "content") uri
            else runCatching {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", File(uri.path!!))
            }.getOrNull()
        if (shareUri == null) {
            Toast.makeText(this, R.string.share_failed, Toast.LENGTH_SHORT).show()
            return
        }
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*")
            .putExtra(Intent.EXTRA_STREAM, shareUri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // Some Android versions refuse to delegate a tree-derived grant and
        // throw here rather than at read time
        runCatching { startActivity(Intent.createChooser(send, getString(R.string.share_file))) }
            .onFailure { Toast.makeText(this, R.string.share_failed, Toast.LENGTH_SHORT).show() }
    }

    /**
     * Best-effort document URI of the folder holding [uri], for the Files app.
     * Null when the source provider does not expose a real filesystem location,
     * which hides the menu item.
     */
    private fun containingFolder(uri: Uri): Uri? = runCatching {
        when {
            uri.scheme == "file" ->
                File(uri.path!!).parent?.let { folderDocUri(it) }
            uri.authority == EXTERNAL_STORAGE_AUTHORITY -> {
                // Document id is "volume:relative/path"; drop the file segment
                val docId = DocumentsContract.getDocumentId(uri)
                val volume = docId.substringBefore(':', "")
                val path = docId.substringAfter(':', "")
                if (volume.isEmpty() || path.isEmpty()) null
                else DocumentsContract.buildDocumentUri(
                    EXTERNAL_STORAGE_AUTHORITY,
                    "$volume:${path.substringBeforeLast('/', "")}"
                )
            }
            uri.authority == DOWNLOADS_AUTHORITY -> {
                val docId = DocumentsContract.getDocumentId(uri)
                if (docId.startsWith("raw:")) {
                    File(docId.removePrefix("raw:")).parent?.let { folderDocUri(it) }
                } else {
                    // Opaque ids (msf:42) at least live under Download
                    DocumentsContract.buildDocumentUri(
                        EXTERNAL_STORAGE_AUTHORITY, "primary:Download"
                    )
                }
            }
            uri.authority == "media" ->
                // Our read grant lets us ask MediaStore for the backing path
                contentResolver.query(uri, arrayOf("_data"), null, null, null)?.use { c ->
                    if (!c.moveToFirst()) null
                    else c.getString(0)?.let { File(it).parent }?.let { folderDocUri(it) }
                }
            else -> null
        }
    }.getOrNull()

    /** Maps an absolute folder path to an ExternalStorageProvider document URI. */
    private fun folderDocUri(path: String): Uri? {
        val primary = Environment.getExternalStorageDirectory().absolutePath
        val docId = when {
            path.startsWith(primary) ->
                "primary:" + path.removePrefix(primary).trimStart('/')
            path.startsWith("/storage/") -> {
                val rest = path.removePrefix("/storage/")
                rest.substringBefore('/') + ":" + rest.substringAfter('/', "")
            }
            else -> return null
        }
        return DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_AUTHORITY, docId)
    }

    private fun openFolder(folder: Uri) {
        // The system Files app (and most file managers) handle VIEW on a
        // directory document; no grant needed, they have provider access
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
        runCatching { startActivity(view) }.onFailure {
            Toast.makeText(this, R.string.no_file_manager, Toast.LENGTH_SHORT).show()
        }
    }

    /** In-document search for WebView-rendered formats via findAllAsync. */
    private fun setUpSearch(toolbar: MaterialToolbar, kind: FileKind) {
        val bar = findViewById<LinearLayout>(R.id.searchBar)
        val input = findViewById<EditText>(R.id.searchInput)
        val count = findViewById<TextView>(R.id.searchCount)
        val searchItem = toolbar.menu.findItem(R.id.action_search)

        val web = webView
        // PDF renders in a WebView but has nothing findable in it: pdf.html draws each
        // page to a canvas with no text layer, so findAllAsync reports no matches
        // however many times the word appears. Offering the box would be offering a
        // search that cannot work. Excluded from the README's list of searchable
        // formats and called out in the 1.5 notes, so this is the code catching up
        // with what was already documented rather than a new limitation.
        if (web == null || kind == FileKind.PDF) {
            searchItem.isVisible = false
            return
        }
        searchItem.isVisible = true

        web.setFindListener { active, total, done ->
            if (done) {
                // Set the spoken form before the text: the live region fires on the text
                // change, and by then the description has to be the one to read out
                count.contentDescription =
                    if (total == 0 && input.text.isNotEmpty()) getString(R.string.no_matches)
                    else if (total > 0) getString(R.string.match_count_spoken, active + 1, total)
                    else null
                count.text =
                    if (total == 0 && input.text.isNotEmpty()) getString(R.string.match_count, 0, 0)
                    else if (total > 0) getString(R.string.match_count, active + 1, total)
                    else ""
            }
        }

        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        searchItem.setOnMenuItemClickListener {
            bar.visibility = LinearLayout.VISIBLE
            input.requestFocus()
            imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            true
        }
        input.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                val q = s?.toString().orEmpty()
                if (q.isEmpty()) {
                    web.clearMatches()
                    count.text = ""
                } else {
                    web.findAllAsync(q)
                }
            }
        })
        input.setOnEditorActionListener { _, _, _ ->
            web.findNext(true)
            true
        }
        findViewById<ImageButton>(R.id.searchPrev).setOnClickListener { web.findNext(false) }
        findViewById<ImageButton>(R.id.searchNext).setOnClickListener { web.findNext(true) }
        findViewById<ImageButton>(R.id.searchClose).setOnClickListener {
            imm.hideSoftInputFromWindow(input.windowToken, 0)
            input.text.clear()
            web.clearMatches()
            bar.visibility = LinearLayout.GONE
        }
    }

    /**
     * Edge to edge is enforced from targetSdk 35 on, so push the layout out of the
     * status bar, display cutout and navigation bar areas.
     */
    private fun applySystemBarInsets(root: View) {
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }
    }

    /** Shared plain text becomes a temp file shown in the text viewer. */
    private fun sharedTextUri(): Uri? {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        return runCatching {
            val f = File(cacheDir, "shared-text.txt")
            f.writeText(text)
            Uri.fromFile(f)
        }.getOrNull()
    }

    private fun resolveDisplayName(uri: Uri): String {
        if (uri.scheme == "content") {
            runCatching {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && cursor.moveToFirst()) {
                        cursor.getString(idx)?.let { return it }
                    }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    }

    private fun showImage(container: FrameLayout, uri: Uri, name: String, ext: String) {
        val imageView = SubsamplingScaleImageView(this)
        imageView.contentDescription = name
        imageView.setBackgroundColor(Color.BLACK)
        imageView.setMinimumScaleType(SubsamplingScaleImageView.SCALE_TYPE_CENTER_INSIDE)
        imageView.maxScale = 12f
        imageView.orientation = Thumbs.exifRotation(contentResolver, uri)
        imageView.setOnImageEventListener(object : SubsamplingScaleImageView.DefaultOnImageEventListener() {
            override fun onImageLoadError(e: Exception) {
                // Some formats decode fine in the WebView even when the region decoder gives up
                container.removeAllViews()
                showWeb(container, uri, FileKind.IMAGE_WEB, name, ext)
            }
        })
        container.addView(imageView, matchParent())
        imageView.setImage(ImageSource.uri(uri))
    }

    private fun showPlayer(container: FrameLayout, uri: Uri, name: String, ext: String) {
        val playerView = PlayerView(this)
        playerView.setBackgroundColor(Color.BLACK)
        playerView.keepScreenOn = true
        playerView.controllerShowTimeoutMs = 2500
        container.addView(playerView, matchParent())

        val exo = ExoPlayer.Builder(this).build()
        player = exo
        playerView.player = exo
        exo.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                exo.release()
                player = null
                container.removeAllViews()
                showWeb(container, uri, FileKind.UNSUPPORTED, name, ext)
            }
        })
        exo.setMediaItem(MediaItem.fromUri(uri))
        exo.prepare()
        exo.playWhenReady = true
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun showWeb(container: FrameLayout, uri: Uri, kind: FileKind, name: String, ext: String) {
        val web = WebView(this)
        webView = web

        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            builtInZoomControls = true
            displayZoomControls = false
            setSupportZoom(true)
            useWideViewPort = true
            loadWithOverviewMode = true
            allowFileAccess = false
            allowContentAccess = false
        }

        val assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        // Neither of these can change while the document is open, and a ranged load
        // asks for hundreds of pieces, so resolve them once here instead of per
        // request. documentLength in particular is a round trip to the provider.
        val total = documentLength(uri)
        val mime = documentMime(ext)

        web.webViewClient = object : WebViewClientCompat() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? {
                // The document is served here rather than through WebViewAssetLoader
                // because a PathHandler is only given the path, and answering range
                // requests needs the Range header off the request itself.
                if (request.url.host == ASSET_HOST &&
                    request.url.path?.startsWith("/doc/") == true
                ) {
                    return docResponse(uri, mime, total, request.requestHeaders["Range"])
                }
                return assetLoader.shouldInterceptRequest(request.url)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean = request.url.host != ASSET_HOST
        }

        container.addView(web, matchParent())
        // The load strategy is decided here, not in the page, so the headers we serve
        // and the loader the page picks cannot disagree
        val ranged = if (useRanges(total)) 1 else 0
        web.loadUrl(
            "https://$ASSET_HOST/assets/viewer/${kind.page}" +
                "?name=${Uri.encode(name)}&ext=${Uri.encode(ext)}&ranged=$ranged" +
                pdfjsFloorParams(kind)
        )
    }

    /**
     * Serves the open document at /doc/<anything>, answering range requests.
     *
     * Told that ranges are available, pdf.js pulls a large file in pieces as it
     * needs them instead of buffering all of it before drawing anything. On a
     * 53 MB scan that read was about 400 ms of a one second open, and it kept the
     * whole document in memory for as long as it was on screen.
     *
     * A fresh stream per request: the page asks for many, and out of order.
     */
    private fun docResponse(
        uri: Uri,
        mime: String,
        total: Long,
        range: String?
    ): WebResourceResponse {
        return try {
            // Ranges are only offered for documents big enough to be worth the extra
            // round trips. Measured on a Nothing Phone 2: a 53 MB scan opened 177 ms
            // faster ranged, while a 251 KB document opened 67 ms slower. Below the
            // threshold one bulk read wins; above it, reading the lot dominates.
            val rangeable = useRanges(total)
            val span = if (rangeable) range?.let { parseRange(it, total) } else null
            if (span == null) {
                val headers = mutableMapOf<String, String>()
                if (rangeable) headers["Accept-Ranges"] = "bytes"
                if (total >= 0) headers["Content-Length"] = total.toString()
                WebResourceResponse(
                    mime, null, 200, "OK", headers,
                    contentResolver.openInputStream(uri)
                )
            } else {
                val (start, end) = span
                WebResourceResponse(
                    mime, null, 206, "Partial Content",
                    mapOf(
                        "Accept-Ranges" to "bytes",
                        "Content-Range" to "bytes $start-$end/$total",
                        "Content-Length" to (end - start + 1).toString()
                    ),
                    slice(uri, start, end)
                )
            }
        } catch (e: Exception) {
            WebResourceResponse(
                "text/plain", "utf-8", 404, "Not Found",
                null, ByteArrayInputStream(ByteArray(0))
            )
        }
    }

    /**
     * Whether to serve this document in ranges. Decided in one place because both
     * the response headers and the page's choice of loader have to agree.
     */
    private fun useRanges(total: Long): Boolean =
        total >= RANGE_THRESHOLD_BYTES

    /**
     * Chromium major version of the WebView that will render the page, from a
     * versionName like "138.0.7204.179".
     *
     * Null when there is no provider to ask, the name is not in that shape, or the
     * number is too low to be a Chromium version at all. A null is treated as new
     * enough: refusing PDFs on a WebView that works would be the worse mistake, and
     * pdf.html's nomodule fallback still covers the oldest engines a null could hide.
     */
    private fun webViewChromiumMajor(): Int? = runCatching {
        WebViewCompat.getCurrentWebViewPackage(this)
            ?.versionName
            ?.substringBefore('.')
            ?.toIntOrNull()
            ?.takeIf { it >= PLAUSIBLE_CHROMIUM_MAJOR }
    }.getOrNull()

    /**
     * "&webview=<major>&needs=<floor>" when the WebView about to render is older than
     * the vendored pdf.js supports, and empty otherwise, including for every other
     * format: pdf.html is the only viewer loaded as an ES module, and the rest are
     * classic scripts that any engine can parse.
     *
     * Both numbers are passed so the floor lives only in Kotlin rather than being
     * repeated as a literal inside a user-facing sentence in the page.
     */
    private fun pdfjsFloorParams(kind: FileKind): String {
        if (kind != FileKind.PDF) return ""
        val major = webViewChromiumMajor() ?: return ""
        if (major >= PDFJS_MIN_CHROMIUM_MAJOR) return ""
        return "&webview=$major&needs=$PDFJS_MIN_CHROMIUM_MAJOR"
    }

    /** Content type for the document, from the extension rather than the provider. */
    private fun documentMime(ext: String): String = when (ext) {
        "svg" -> "image/svg+xml"
        else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }

    /** Length in bytes, or -1 when the provider declines to say. */
    private fun documentLength(uri: Uri): Long = runCatching {
        contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length }
    }.getOrNull()?.takeIf { it >= 0 } ?: -1L

    /**
     * "bytes=start-end" resolved against a known total. Null means serve the whole
     * thing: an unparseable header, an unsatisfiable one, or a provider that would
     * not give us a length to range against.
     */
    private fun parseRange(header: String, total: Long): Pair<Long, Long>? {
        if (total <= 0) return null
        // Only the first range of a set; pdf.js never asks for more than one
        val spec = header.substringAfter("bytes=", "").substringBefore(',').trim()
        if (spec.isEmpty()) return null
        val start = spec.substringBefore('-').trim().toLongOrNull() ?: return null
        val end = spec.substringAfter('-').trim().toLongOrNull() ?: (total - 1)
        if (start < 0 || start > end || start >= total) return null
        return start to minOf(end, total - 1)
    }

    /** Exactly [start, end], seeking to the offset rather than reading up to it. */
    private fun slice(uri: Uri, start: Long, end: Long): InputStream {
        val pfd = contentResolver.openFileDescriptor(uri, "r")
            ?: throw java.io.IOException("cannot open $uri")
        val stream = java.io.FileInputStream(pfd.fileDescriptor)
        // Seekable for anything file backed; a pipe has to be read through instead
        runCatching { stream.channel.position(start) }
            .onFailure { runCatching { stream.skip(start) } }
        return LimitedInputStream(stream, end - start + 1, pfd)
    }

    /** Stops at [remaining] bytes, and closes the descriptor along with the stream. */
    private class LimitedInputStream(
        private val source: InputStream,
        private var remaining: Long,
        private val alsoClose: java.io.Closeable
    ) : InputStream() {
        override fun read(): Int {
            if (remaining <= 0) return -1
            return source.read().also { if (it >= 0) remaining-- }
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (remaining <= 0) return -1
            val n = source.read(b, off, minOf(len.toLong(), remaining).toInt())
            if (n > 0) remaining -= n
            return n
        }

        override fun available(): Int = minOf(source.available().toLong(), remaining).toInt()

        override fun close() {
            runCatching { source.close() }
            runCatching { alsoClose.close() }
        }
    }

    private fun matchParent() = FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    )

    override fun onStop() {
        player?.pause()
        super.onStop()
    }

    override fun onDestroy() {
        player?.release()
        player = null
        webView?.destroy()
        webView = null
        super.onDestroy()
    }
}
