package com.pufy.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.rounded.*
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import com.pufy.app.ui.theme.Pufy

/** "#RRGGBB" → renk (iOS Color(hex:)) */
fun colorFromHex(hex: String?): Color? {
    val h = hex?.trim()?.removePrefix("#") ?: return null
    if (h.length != 6 && h.length != 8) return null
    val v = h.toLongOrNull(16) ?: return null
    return if (h.length == 6) Color(0xFF000000 or v) else Color(v)
}

/**
 * Mini uygulamaların ikonları iOS'ta SF Symbol adıyla kayıtlı (iPhone ile eşitlendiği için ad değişmez).
 * Android'de en yakın Material simgesine çevrilir; anahtar kelimeye göre eşleşir.
 */
object Symbols {
    private val table: List<Pair<String, ImageVector>> = listOf(
        "fork.knife" to Icons.Rounded.Restaurant, "cart" to Icons.Rounded.ShoppingCart, "bag" to Icons.Rounded.ShoppingBag,
        "cup" to Icons.Rounded.LocalCafe, "mug" to Icons.Rounded.LocalCafe, "leaf" to Icons.Rounded.Eco, "drop" to Icons.Rounded.WaterDrop,
        "flame" to Icons.Rounded.LocalFireDepartment, "heart" to Icons.Rounded.Favorite, "figure" to Icons.Rounded.DirectionsRun,
        "dumbbell" to Icons.Rounded.FitnessCenter, "bed" to Icons.Rounded.Bed, "moon" to Icons.Rounded.DarkMode, "sun" to Icons.Rounded.WbSunny,
        "cloud" to Icons.Rounded.Cloud, "snow" to Icons.Rounded.AcUnit, "bolt" to Icons.Rounded.Bolt, "timer" to Icons.Rounded.Timer,
        "stopwatch" to Icons.Rounded.Timer, "alarm" to Icons.Rounded.Alarm, "clock" to Icons.Rounded.Schedule, "calendar" to Icons.Rounded.CalendarMonth,
        "checklist" to Icons.Rounded.Checklist, "checkmark" to Icons.Rounded.TaskAlt, "list" to Icons.AutoMirrored.Rounded.List,
        "note" to Icons.AutoMirrored.Rounded.Notes, "doc" to Icons.Rounded.Description, "book" to Icons.AutoMirrored.Rounded.MenuBook,
        "pencil" to Icons.Rounded.Edit, "paintbrush" to Icons.Rounded.Brush, "paintpalette" to Icons.Rounded.Palette, "photo" to Icons.Rounded.Image,
        "camera" to Icons.Rounded.PhotoCamera, "music" to Icons.Rounded.MusicNote, "headphones" to Icons.Rounded.Headphones, "mic" to Icons.Rounded.Mic,
        "play" to Icons.Rounded.PlayArrow, "film" to Icons.Rounded.Movie, "tv" to Icons.Rounded.Tv, "gamecontroller" to Icons.Rounded.SportsEsports,
        "dice" to Icons.Rounded.Casino, "puzzle" to Icons.Rounded.Extension, "trophy" to Icons.Rounded.EmojiEvents, "sportscourt" to Icons.Rounded.SportsSoccer,
        "soccer" to Icons.Rounded.SportsSoccer, "basketball" to Icons.Rounded.SportsBasketball, "football" to Icons.Rounded.SportsSoccer,
        "car" to Icons.Rounded.DirectionsCar, "bus" to Icons.Rounded.DirectionsBus, "tram" to Icons.Rounded.Tram, "airplane" to Icons.Rounded.Flight,
        "map" to Icons.Rounded.Map, "location" to Icons.Rounded.LocationOn, "globe" to Icons.Rounded.Public, "house" to Icons.Rounded.Home,
        "building" to Icons.Rounded.Apartment, "dollarsign" to Icons.Rounded.AttachMoney, "turkishlirasign" to Icons.Rounded.CurrencyLira,
        "lira" to Icons.Rounded.CurrencyLira, "creditcard" to Icons.Rounded.CreditCard, "banknote" to Icons.Rounded.Payments,
        "chart" to Icons.AutoMirrored.Rounded.ShowChart, "percent" to Icons.Rounded.Percent, "function" to Icons.Rounded.Functions,
        "plus.forwardslash.minus" to Icons.Rounded.Calculate, "calculator" to Icons.Rounded.Calculate, "number" to Icons.Rounded.Tag,
        "brain" to Icons.Rounded.Psychology, "lightbulb" to Icons.Rounded.Lightbulb, "sparkles" to Icons.Rounded.AutoAwesome, "star" to Icons.Rounded.Star,
        "wand" to Icons.Rounded.AutoFixHigh, "bubble" to Icons.Rounded.ChatBubble, "message" to Icons.AutoMirrored.Rounded.Chat,
        "envelope" to Icons.Rounded.Mail, "phone" to Icons.Rounded.Phone, "person" to Icons.Rounded.Person, "gift" to Icons.Rounded.CardGiftcard,
        "pawprint" to Icons.Rounded.Pets, "tree" to Icons.Rounded.Park, "pills" to Icons.Rounded.Medication, "cross" to Icons.Rounded.LocalHospital,
        "stethoscope" to Icons.Rounded.MedicalServices, "graduationcap" to Icons.Rounded.School, "translate" to Icons.Rounded.Translate,
        "character" to Icons.Rounded.Translate, "textformat" to Icons.Rounded.TextFields, "qrcode" to Icons.Rounded.QrCode2,
        "lock" to Icons.Rounded.Lock, "key" to Icons.Rounded.Key, "gear" to Icons.Rounded.Settings, "wrench" to Icons.Rounded.Build,
        "hammer" to Icons.Rounded.Handyman, "cpu" to Icons.Rounded.Memory, "terminal" to Icons.Rounded.Terminal, "chevron.left.forwardslash" to Icons.Rounded.Code,
        "wifi" to Icons.Rounded.Wifi, "battery" to Icons.Rounded.BatteryFull, "flag" to Icons.Rounded.Flag, "bell" to Icons.Rounded.Notifications,
        "target" to Icons.Rounded.TrackChanges, "scope" to Icons.Rounded.TrackChanges, "square.grid" to Icons.Rounded.GridView,
        "app" to Icons.Outlined.Apps,
    )

    fun icon(name: String?): ImageVector {
        val n = name?.lowercase() ?: return Icons.Outlined.Apps
        return table.firstOrNull { n == it.first || n.startsWith(it.first + ".") || n.startsWith(it.first) }?.second
            ?: table.firstOrNull { n.contains(it.first) }?.second ?: Icons.Outlined.Apps
    }
}

/** iOS MiniAppIconTile: renkli yuvarlak kare + simge */
@Composable
fun AppIconTile(icon: String?, colorHex: String?, size: Dp, modifier: Modifier = Modifier) {
    val c = Pufy.colors
    val tint = colorFromHex(colorHex)
    val bg = tint ?: c.primary
    val shape = RoundedCornerShape(size * 0.26f)
    Box(modifier.size(size).shadow(size * 0.08f, shape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
        .clip(shape).background(Brush.verticalGradient(listOf(bg.copy(alpha = 0.92f).compositeOn(Color.White), bg))),
        contentAlignment = Alignment.Center) {
        Icon(Symbols.icon(icon), null, Modifier.size(size * 0.46f), tint = if (tint == null) c.onPrimary else Color.White)
    }
}

private fun Color.compositeOn(under: Color): Color {
    val a = alpha
    return Color(red * a + under.red * (1 - a), green * a + under.green * (1 - a), blue * a + under.blue * (1 - a), 1f)
}
