package com.pufy.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pufy.app.apps.AppBuilder
import com.pufy.app.apps.MiniAppSecrets
import com.pufy.app.core.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AppBuilderTest {

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        Settings.init(context)
    }

    @Test
    fun parseSecretsExtractsValidKeys() {
        val sample = """
            <<<META {"name": "Hava Durumu", "secrets": {"OPENWEATHER_KEY": "  xyz123  ", "EMPTY": ""}}>>>
            <<<FILE index.html>>>
            <h1>Hava</h1>
            <<<END>>>
        """.trimIndent()

        val secrets = AppBuilder.parseSecrets(sample)
        assertEquals(mapOf("OPENWEATHER_KEY" to "xyz123"), secrets)
    }

    @Test
    fun miniAppSecretsMergeAndGet() {
        val folder = "test_app_folder"
        try {
            MiniAppSecrets.removeAll(folder)
            assertEquals(emptyMap<String, String>(), MiniAppSecrets.all(folder))

            MiniAppSecrets.merge(mapOf("API_KEY" to "abc-secret-key"), folder)
            assertEquals("abc-secret-key", MiniAppSecrets.get("API_KEY", folder))
            assertNull(MiniAppSecrets.get("NON_EXISTENT", folder))

            MiniAppSecrets.merge(mapOf("OTHER_KEY" to "def-456"), folder)
            assertEquals("abc-secret-key", MiniAppSecrets.get("API_KEY", folder))
            assertEquals("def-456", MiniAppSecrets.get("OTHER_KEY", folder))
        } finally {
            MiniAppSecrets.removeAll(folder)
        }
    }
}
