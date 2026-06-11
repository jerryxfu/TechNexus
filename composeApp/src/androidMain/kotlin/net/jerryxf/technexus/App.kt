package net.jerryxf.technexus

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import net.jerryxf.technexus.views.AppNavHost

@Composable
fun App() {
    val nav = rememberNavController()
    val navBackStackEntry by nav.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    MaterialTheme(colorScheme()) {
        Scaffold(
            bottomBar = {
                NavigationBar(windowInsets = NavigationBarDefaults.windowInsets) {
                    Destination.entries.forEach { destination ->
                        NavigationBarItem(
                            currentRoute == destination.route,
                            {
                                nav.navigate(destination.route) {
                                    // Avoid building up a large back stack
                                    popUpTo(nav.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            destination.icon,
                            label = { Text(destination.label) }
                        )
                    }
                }
            }
        ) { contentPadding ->
            AppNavHost(nav, Destination.default, Modifier.padding(contentPadding))
        }
    }
}

enum class Destination(
    val route: String,
    val label: String,
    val icon: @Composable () -> Unit
) {
    SCHEDULE("schedule", "Schedule", ::CalendarIcon),
    PIT("pit", "Pit", ::HammerIcon),
    TECHBOTICS("techbotics", "TechBotics", ::AnalyticsIcon),
    SETTINGS("settings", "Settings", ::SettingsIcon),
    OTHER("others", "Others", ::ThreeBarsMenu);

    companion object {
        val default = SCHEDULE
    }
}
