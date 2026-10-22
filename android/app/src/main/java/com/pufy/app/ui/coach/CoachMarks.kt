package com.pufy.app.ui.coach

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pufy.app.core.Settings
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.components.pressable

// MARK: - İlk Açılış İpuçları (Coach Marks)
//
// 1. Uygulamalarına ulaş: iki parmak kıstırma animasyonu
// 2. Menü: ≡ butonu spotlight
// 3. Her şeyi sor: giriş alanı spotlight

@Composable
fun CoachMarksOverlay(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val c = Pufy.colors
    val density = LocalDensity.current
    val view = LocalView.current
    var currentStep by remember { mutableIntStateOf(0) }
    var didCompletePinch by remember { mutableStateOf(false) }

    // Animasyonlar: 1.6s parmak kıstırma döngüsü, 1.0s nabız
    val transition = rememberInfiniteTransition(label = "coach_anims")
    val pinchPhase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 0.85f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pinchPhase"
    )
    val pulse by transition.animateFloat(
        initialValue = 1.0f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )

    fun advance() {
        if (currentStep < 2) {
            currentStep++
        } else {
            Settings.setBool(Settings.COACH_MARKS_COMPLETED, true)
            onDismiss()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(currentStep) {
                if (currentStep == 0) {
                    detectTransformGestures { _, _, zoom, _ ->
                        if (zoom < 0.88f && !didCompletePinch) {
                            didCompletePinch = true
                            Haptics.success(view)
                            currentStep = 1
                        }
                    }
                }
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                advance()
            }
    ) {
        // Spotlight karartma ve oyuk katmanı
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer(alpha = 0.99f) // BlendMode.Clear için offscreen buffer
        ) {
            drawRect(Color.Black.copy(alpha = 0.55f))

            if (currentStep == 1) {
                // Sol üstteki ≡ düğmesi spotlight
                val topPadding = 48.dp.toPx()
                val leftPadding = 38.dp.toPx()
                val radius = 26.dp.toPx()
                drawCircle(
                    color = Color.Transparent,
                    radius = radius,
                    center = Offset(leftPadding, topPadding),
                    blendMode = BlendMode.Clear
                )
                // Nabız çerçevesi
                drawCircle(
                    color = Color.White.copy(alpha = 0.5f),
                    radius = radius * pulse,
                    center = Offset(leftPadding, topPadding),
                    style = Stroke(width = 2.dp.toPx())
                )
            } else if (currentStep == 2) {
                // Alttaki composer spotlight
                val composerHeight = 56.dp.toPx()
                val composerWidth = size.width - 32.dp.toPx()
                val left = 16.dp.toPx()
                val top = size.height - 76.dp.toPx()
                val rrect = RoundRect(
                    rect = Rect(left, top, left + composerWidth, top + composerHeight),
                    cornerRadius = CornerRadius(28.dp.toPx(), 28.dp.toPx())
                )
                val path = Path().apply { addRoundRect(rrect) }
                drawPath(path, color = Color.Transparent, blendMode = BlendMode.Clear)
                drawRoundRect(
                    color = Color.White.copy(alpha = 0.5f),
                    topLeft = Offset(left - 2.dp.toPx(), top - 2.dp.toPx()),
                    size = Size(composerWidth + 4.dp.toPx(), composerHeight + 4.dp.toPx()),
                    cornerRadius = CornerRadius(30.dp.toPx(), 30.dp.toPx()),
                    style = Stroke(width = 2.dp.toPx())
                )
            }
        }

        // İçerik ve Cam Kartlar
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            when (currentStep) {
                0 -> {
                    Spacer(Modifier.weight(1f))

                    // İki parmak kıstırma animasyonu (kodla çizim, ~44dp parmak uçları)
                    if (didCompletePinch) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                Icons.Outlined.CheckCircle,
                                null,
                                modifier = Modifier.size(54.dp),
                                tint = c.primary
                            )
                            Text(
                                tx("Harika!", "Nice!"),
                                style = PufyType.title.copy(fontWeight = FontWeight.Bold),
                                color = Color.White
                            )
                        }
                    } else {
                        val spread = (60.dp * (1.0f - pinchPhase)).coerceAtLeast(16.dp)
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(spread * 2),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            FingerCircle()
                            FingerCircle()
                        }
                    }

                    Spacer(Modifier.height(36.dp))

                    CoachCard(
                        title = if (didCompletePinch) tx("Harika!", "Nice!") else tx("Uygulamalarına ulaş", "Reach your apps"),
                        description = if (didCompletePinch)
                            tx("Şimdi diğer özelliklere göz atalım.", "Now let's look at a few more things.")
                        else
                            tx("İki parmakla kıstır. Uygulamalarına buradan geçersin. Üstteki ızgara düğmesi de aynı işi yapar.", "Pinch with two fingers to switch to your apps. The grid button at the top does the same."),
                        step = 1,
                        totalSteps = 3,
                        onSkip = {
                            Settings.setBool(Settings.COACH_MARKS_COMPLETED, true)
                            onDismiss()
                        },
                        onNext = { advance() },
                        modifier = Modifier.padding(horizontal = 24.dp)
                    )

                    Spacer(Modifier.weight(1f))
                }
                1 -> {
                    Spacer(Modifier.statusBarsPadding().height(70.dp))

                    CoachCard(
                        title = tx("Menü", "Menu"),
                        description = tx("Sohbetlerin, notların, hatırlatıcıların ve Kişisel Ağ burada. Soldan sağa kaydırarak da açabilirsin.", "Your chats, notes, reminders and Personal Network live here. You can also swipe from left to right."),
                        step = 2,
                        totalSteps = 3,
                        onSkip = {
                            Settings.setBool(Settings.COACH_MARKS_COMPLETED, true)
                            onDismiss()
                        },
                        onNext = { advance() },
                        modifier = Modifier.padding(horizontal = 24.dp)
                    )

                    Spacer(Modifier.weight(1f))
                }
                2 -> {
                    Spacer(Modifier.weight(1f))

                    CoachCard(
                        title = tx("Her şeyi sor", "Ask anything"),
                        description = tx("Yaz ya da mikrofona bas. Hatırlatıcı kur, araştırma yaptır, 'yarın 9'da hatırlat' de.", "Type or tap the mic. Set reminders, run research, or just say 'remind me at 9 tomorrow'."),
                        step = 3,
                        totalSteps = 3,
                        onSkip = {
                            Settings.setBool(Settings.COACH_MARKS_COMPLETED, true)
                            onDismiss()
                        },
                        onNext = { advance() },
                        modifier = Modifier.padding(horizontal = 24.dp)
                    )

                    Spacer(Modifier.navigationBarsPadding().height(90.dp))
                }
            }
        }
    }
}

@Composable
private fun FingerCircle() {
    Box(
        modifier = Modifier
            .size(44.dp)
            .shadow(10.dp, CircleShape)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.85f))
            .border(4.dp, Color.White.copy(alpha = 0.4f), CircleShape)
    )
}

@Composable
private fun CoachCard(
    title: String,
    description: String,
    step: Int,
    totalSteps: Int,
    onSkip: () -> Unit,
    onNext: () -> Unit,
    modifier: Modifier = Modifier
) {
    val c = Pufy.colors
    val view = LocalView.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(c.secondaryBackground.copy(alpha = 0.95f))
            .border(0.5.dp, c.text.copy(alpha = 0.08f), RoundedCornerShape(22.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(title, style = PufyType.title.copy(fontWeight = FontWeight.Bold), color = c.text)
        Text(description, style = PufyType.subheadline, color = c.secondaryText)

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Adım noktaları
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in 1..totalSteps) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(if (i == step) c.text else c.text.copy(alpha = 0.2f))
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            Text(
                tx("Atla", "Skip"),
                style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium),
                color = c.secondaryText,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .pressable { Haptics.light(view); onSkip() }
                    .padding(horizontal = 12.dp, vertical = 7.dp)
            )

            Spacer(Modifier.size(8.dp))

            Text(
                if (step == totalSteps) tx("Başla", "Start") else tx("Sonraki", "Next"),
                style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                color = c.onPrimary,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(c.primary)
                    .pressable { Haptics.light(view); onNext() }
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}

// MARK: - Bağlamsal Tek Seferlik İpucu Balonu (Contextual Tooltip)

@Composable
fun HintBubble(
    text: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val c = Pufy.colors
    val view = LocalView.current

    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(c.secondaryBackground.copy(alpha = 0.95f))
            .border(0.5.dp, c.text.copy(alpha = 0.12f), CircleShape)
            .pressable { Haptics.light(view); onDismiss() }
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(Icons.Outlined.AutoAwesome, null, modifier = Modifier.size(13.dp), tint = c.primary)
        Text(
            text,
            style = PufyType.caption.copy(fontWeight = FontWeight.Medium),
            color = c.text
        )
        Icon(
            Icons.Outlined.Close,
            null,
            modifier = Modifier
                .size(14.dp)
                .clickable { Haptics.light(view); onDismiss() },
            tint = c.secondaryText
        )
    }
}

private fun tx(tr: String, en: String) = if (com.pufy.app.core.AppLocales.isEnglish()) en else tr
