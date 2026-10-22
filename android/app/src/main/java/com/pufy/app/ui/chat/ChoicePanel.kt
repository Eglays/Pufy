package com.pufy.app.ui.chat

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pufy.app.R
import com.pufy.app.core.TR
import com.pufy.app.data.ChoiceQuestion
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs

// iOS ChoicePanel: yapay zekanın sorduğu seçenekli sorular yazma çubuğunun üstünde.
// Tek seçimli tek soru → dokununca gönderilir; çoklu ya da birden fazla soru → seç, "Gönder".

object Choices {
    private val multiCues = listOf("neler", "hangileri", "birden fazla", "birden çok", "seçebilirsin", "hepsini", "which ones", "select all")
    private val plural = Regex("hangi\\s+\\p{L}+(ler|lar)\\b")
    fun isMulti(q: ChoiceQuestion): Boolean {
        if (q.multi == true) return true
        val t = q.q.lowercase(TR)
        return multiCues.any { t.contains(it) } || plural.containsMatchIn(t)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChoicePanel(questions: List<ChoiceQuestion>, onSubmit: (String) -> Unit, onDismiss: () -> Unit, onCollapse: () -> Unit) {
    val c = Pufy.colors
    val shown = questions.take(3)
    val instant = shown.size == 1 && !Choices.isMulti(shown[0])
    val answers = remember(questions) { mutableStateMapOf<Int, List<String>>() }
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.36f).dp

    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.heightIn(max = maxHeight).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            shown.forEachIndexed { index, q ->
                val multi = Choices.isMulti(q)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(q.q, style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, modifier = Modifier.weight(1f))
                        if (index == 0) {
                            Box(Modifier.size(28.dp).pressable(onClick = onCollapse), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.KeyboardArrowDown, stringResource(R.string.collapse_action), Modifier.size(18.dp), tint = c.secondaryText)
                            }
                            Box(Modifier.size(28.dp).pressable(onClick = onDismiss), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.Close, stringResource(R.string.close), Modifier.size(16.dp), tint = c.secondaryText)
                            }
                        }
                    }
                    if (multi) Text(stringResource(R.string.multiple_choice_hint), style = PufyType.caption, color = c.secondaryText)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        q.options.take(8).forEach { option ->
                            val selected = answers[index]?.contains(option) == true
                            val bg by animateColorAsState(if (selected) c.primary else c.soft, Springs.quick(), label = "bg")
                            val fg by animateColorAsState(if (selected) c.onPrimary else c.onSoft, Springs.quick(), label = "fg")
                            Text(option, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = fg,
                                modifier = Modifier.clip(CircleShape).background(bg)
                                    .border(0.5.dp, c.text.copy(alpha = 0.06f), CircleShape)
                                    .pressable {
                                        if (instant) { onSubmit(option); return@pressable }
                                        val cur = answers[index].orEmpty()
                                        val next = if (multi) (if (option in cur) cur - option else cur + option) else (if (cur == listOf(option)) emptyList() else listOf(option))
                                        if (next.isEmpty()) answers.remove(index) else answers[index] = next
                                    }
                                    .padding(horizontal = 14.dp, vertical = 9.dp))
                        }
                    }
                }
            }
        }
        if (!instant) {
            val ready = answers.isNotEmpty()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (ready) stringResource(R.string.choices_answered_count, answers.size, shown.size) else stringResource(R.string.make_your_choices), style = PufyType.caption, color = c.secondaryText)
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.send_action), style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold),
                    color = if (ready) c.onPrimary else c.secondaryText,
                    modifier = Modifier.clip(CircleShape).background(if (ready) c.primary else c.disabled)
                        .pressable(enabled = ready) {
                            onSubmit(shown.indices.mapNotNull { i -> answers[i]?.takeIf { it.isNotEmpty() }?.let { "${shown[i].q} ${it.joinToString(", ")}" } }.joinToString("\n"))
                        }.padding(horizontal = 18.dp, vertical = 9.dp))
            }
        }
    }
}
