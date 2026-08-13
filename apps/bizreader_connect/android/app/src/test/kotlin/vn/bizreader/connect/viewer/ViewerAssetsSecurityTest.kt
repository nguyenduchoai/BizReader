package vn.bizreader.connect.viewer

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class ViewerAssetsSecurityTest {
    @Test
    fun everyViewerPageHasAnOfflineContentSecurityPolicy() {
        val viewerDirectory = File("src/main/assets/viewer")
            .takeIf { it.isDirectory }
            ?: File("app/src/main/assets/viewer")
        val pages = listOf(
            "docx.html",
            "imgweb.html",
            "md.html",
            "pdf.html",
            "pptx.html",
            "text.html",
            "unsupported.html",
            "xlsx.html",
        )

        for (page in pages) {
            val html = File(viewerDirectory, page).readText()
            assertTrue("$page is missing CSP", html.contains("Content-Security-Policy"))
            assertTrue("$page can connect outside the app", html.contains("connect-src 'self'"))
            assertTrue("$page can embed frames", html.contains("frame-src 'none'"))
            assertTrue("$page can run plugins", html.contains("object-src 'none'"))
        }
    }
}
