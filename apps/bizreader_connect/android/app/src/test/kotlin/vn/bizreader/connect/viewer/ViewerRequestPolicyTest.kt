package vn.bizreader.connect.viewer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ViewerRequestPolicyTest {
    @Test
    fun allowsOnlyTheInternalHostForHttpResources() {
        assertFalse(
            ViewerRequestPolicy.blocksNetworkRequest(
                "https",
                ViewerRequestPolicy.ASSET_HOST,
            ),
        )
        assertFalse(
            ViewerRequestPolicy.blocksNetworkRequest(
                "HTTP",
                ViewerRequestPolicy.ASSET_HOST.uppercase(),
            ),
        )
        assertTrue(ViewerRequestPolicy.blocksNetworkRequest("https", "example.com"))
        assertTrue(ViewerRequestPolicy.blocksNetworkRequest("http", null))
    }

    @Test
    fun doesNotBlockNonNetworkResources() {
        assertFalse(ViewerRequestPolicy.blocksNetworkRequest("blob", null))
        assertFalse(ViewerRequestPolicy.blocksNetworkRequest("data", null))
        assertFalse(ViewerRequestPolicy.blocksNetworkRequest("content", "provider"))
    }
}
