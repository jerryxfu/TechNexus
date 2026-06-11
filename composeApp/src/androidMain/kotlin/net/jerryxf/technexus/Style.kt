package net.jerryxf.technexus

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun colorScheme() = MaterialTheme.colorScheme.copy()

@Composable
fun CalendarIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.CalendarMonth,
    "calendar_icon",
    modifier
)

@Composable
fun HammerIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Build,
    "hammer_icon",
    modifier
)

@Composable
fun AnalyticsIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Analytics,
    "analytics_icon",
    modifier
)

@Composable
fun TimerIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Timer,
    "timer_icon",
    modifier
)

@Composable
fun SettingsIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Settings,
    "settings_icon",
    modifier
)

@Composable
fun FlagIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Flag,
    "flag_icon",
    modifier
)

@Composable
fun ClockIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.Schedule,
    "clock_icon",
    modifier
)

@Composable
fun HumanIcon(modifier: Modifier = Modifier) = Icon(
    Icons.AutoMirrored.Rounded.DirectionsWalk,
    "human_icon",
    modifier
)

@Composable
fun HourglassIcon(modifier: Modifier = Modifier) = Icon(
    Icons.Rounded.HourglassBottom,
    "hourglass_icon",
    modifier
)

val roundCorners = RoundedCornerShape(5.dp)
