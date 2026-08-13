package vn.bizreader.connect

import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import vn.bizreader.connect.viewer.ViewerActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vn.bizreader.connect/universal_viewer",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank() || !File(path).isFile) {
                result.error("FILE_NOT_FOUND", "Không tìm thấy tệp đã chọn.", null)
                return@setMethodCallHandler
            }

            val file = File(path)
            val uri = runCatching {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            }.getOrElse {
                result.error("FILE_ACCESS", "Không thể cấp quyền đọc tệp đã chọn.", null)
                return@setMethodCallHandler
            }
            val mime = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
            startActivity(
                Intent(this, ViewerActivity::class.java)
                    .setDataAndType(uri, mime)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            result.success(null)
        }
    }
}
