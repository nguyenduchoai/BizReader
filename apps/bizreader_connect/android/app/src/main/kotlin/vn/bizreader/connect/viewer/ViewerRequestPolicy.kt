package vn.bizreader.connect.viewer

internal object ViewerRequestPolicy {
    const val ASSET_HOST = "appassets.androidplatform.net"

    fun blocksNetworkRequest(scheme: String?, host: String?): Boolean {
        val isNetworkRequest = scheme.equals("http", ignoreCase = true) ||
            scheme.equals("https", ignoreCase = true)
        return isNetworkRequest && !host.equals(ASSET_HOST, ignoreCase = true)
    }
}
