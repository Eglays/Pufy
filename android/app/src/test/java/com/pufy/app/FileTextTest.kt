package com.pufy.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pufy.app.core.FileTextExtractor
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FileTextTest {

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        PDFBoxResourceLoader.init(context)
    }

    @Test
    fun testSmallTxtWithTurkishCharacters() {
        val sampleText = "Pufy Agent Türkçe metin çıkarma testi: ığüşöç İĞÜŞÖÇ."
        val bytes = sampleText.toByteArray(StandardCharsets.UTF_8)
        val attachment = FileTextExtractor.processBytes("deneme.txt", bytes)

        assertEquals("deneme.txt", attachment.name)
        assertEquals("text", attachment.kind)
        assertEquals(sampleText, attachment.text)
        assertFalse(attachment.truncated)
    }

    @Test
    fun testDocxGeneratedInZip() {
        val xmlContent = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                <w:body>
                    <w:p>
                        <w:r>
                            <w:t>Pufy Agent DOCX Testi</w:t>
                        </w:r>
                    </w:p>
                    <w:p>
                        <w:r>
                            <w:t>İkinci paragraf metni.</w:t>
                        </w:r>
                    </w:p>
                </w:body>
            </w:document>
        """.trimIndent()

        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zip ->
            zip.putNextEntry(ZipEntry("word/document.xml"))
            zip.write(xmlContent.toByteArray(StandardCharsets.UTF_8))
            zip.closeEntry()
        }
        val docxBytes = baos.toByteArray()

        val attachment = FileTextExtractor.processBytes("rapor.docx", docxBytes)
        assertEquals("rapor.docx", attachment.name)
        assertEquals("docx", attachment.kind)
        assertTrue(attachment.text.contains("Pufy Agent DOCX Testi"))
        assertTrue(attachment.text.contains("İkinci paragraf metni."))
        assertFalse(attachment.truncated)
    }

    @Test
    fun testSixtyThousandCharacterTruncation() {
        val repeatPattern = "ABCDEFGH12345678" // 16 chars
        val longText = repeatPattern.repeat(5000) // 80,000 chars
        val bytes = longText.toByteArray(StandardCharsets.UTF_8)

        val attachment = FileTextExtractor.processBytes("uzun_metin.txt", bytes)
        assertEquals("uzun_metin.txt", attachment.name)
        assertEquals(60_000, attachment.text.length)
        assertTrue(attachment.truncated)
        assertEquals(longText.take(60_000), attachment.text)
    }

    @Test
    fun testPdfGeneratedWithPdfBoxAndRead() {
        val doc = PDDocument()
        val page = PDPage()
        doc.addPage(page)

        val contentStream = PDPageContentStream(doc, page)
        contentStream.beginText()
        contentStream.setFont(PDType1Font.HELVETICA_BOLD, 14f)
        contentStream.newLineAtOffset(100f, 700f)
        contentStream.showText("Pufy PDFBox Test Document")
        contentStream.endText()
        contentStream.close()

        val baos = ByteArrayOutputStream()
        doc.save(baos)
        doc.close()

        val pdfBytes = baos.toByteArray()
        val attachment = FileTextExtractor.processBytes("belge.pdf", pdfBytes)

        assertEquals("belge.pdf", attachment.name)
        assertEquals("pdf", attachment.kind)
        assertEquals(1, attachment.pageCount)
        assertTrue(attachment.text.contains("Pufy PDFBox Test Document"))
        assertFalse(attachment.truncated)
    }
}
