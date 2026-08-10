package vn.bizreader.connect.viewer

import org.junit.Assert.assertEquals
import org.junit.Test

class FileKindTest {
    @Test
    fun detectsSupportedDocumentFamilies() {
        assertEquals(FileKind.PDF, FileKind.detect("pdf", null))
        assertEquals(FileKind.DOCX, FileKind.detect("docx", null))
        assertEquals(FileKind.XLSX, FileKind.detect("xlsx", null))
        assertEquals(FileKind.XLSX, FileKind.detect("ods", null))
        assertEquals(FileKind.PPTX, FileKind.detect("pptx", null))
        assertEquals(FileKind.MD, FileKind.detect("md", null))
        assertEquals(FileKind.TEXT, FileKind.detect("dart", null))
    }

    @Test
    fun detectsImagesAndMedia() {
        assertEquals(FileKind.IMAGE, FileKind.detect("jpg", null))
        assertEquals(FileKind.IMAGE_WEB, FileKind.detect("svg", null))
        assertEquals(FileKind.PLAYER, FileKind.detect("mp4", null))
        assertEquals(FileKind.PLAYER, FileKind.detect("mp3", null))
    }

    @Test
    fun rejectsLegacyOfficeFormats() {
        assertEquals(FileKind.UNSUPPORTED, FileKind.detect("doc", null))
        assertEquals(FileKind.UNSUPPORTED, FileKind.detect("ppt", null))
    }
}
