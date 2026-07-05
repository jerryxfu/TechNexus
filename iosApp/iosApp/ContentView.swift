import ComposeApp
import SwiftUI

struct ContentView: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            tabViewModern
        } else {
            tabViewLegacy
        }
    }

    @available(iOS 26.0, *)
    private var tabViewModern: some View {
        TabView {
            Tab("Schedule", systemImage: "calendar.badge") {
                ScheduleView()
            }

            Tab("Pit", systemImage: "hammer") {
                PitTabView()
            }

            Tab("TechBotics", systemImage: "chart.bar") {
                PlaceholderView(title: "Stats", icon: "chart.bar")
            }

            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var tabViewLegacy: some View {
        TabView {
            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar.badge")
                }

            PitTabView()
                .tabItem {
                    Label("Pit", systemImage: "hammer")
                }

            PlaceholderView(title: "TechBotics", icon: "chart.bar")
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

// MARK: - Placeholder

private struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
