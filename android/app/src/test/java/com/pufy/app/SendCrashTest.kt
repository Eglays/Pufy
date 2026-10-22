package com.pufy.app

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import com.pufy.app.ai.ChatEngine
import com.pufy.app.ui.RootScreen
import com.pufy.app.ui.theme.PufyTheme
import org.junit.Rule
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w400dp-h860dp-xxhdpi")
class SendCrashTest {
    @get:Rule val rule = createComposeRule()

    @Test fun sendDoesNotCrash() {
        com.pufy.app.ai.AiClient.endpoint = "http://127.0.0.1:8799"
        com.pufy.app.ai.AiClient.apiKey = "test"
        rule.setContent { PufyTheme { RootScreen() } }
        rule.waitForIdle()
        rule.runOnUiThread { ChatEngine.send("merhaba nasılsın") }
        repeat(40) { rule.mainClock.advanceTimeBy(250); shadowOf(android.os.Looper.getMainLooper()).idle(); Thread.sleep(150) }
        rule.onNode(androidx.compose.ui.test.isRoot()).captureRoboImage("build/screens/07-cevap.png")
        println("SESSION: " + ChatEngine.currentSession?.messages?.map { it.role + ":" + it.content.take(80) })
    }
}
