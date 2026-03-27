//
//  RootView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI

struct RootView: View {
    let services: AppServices
    @State private var showOnboarding: Bool
    @State private var selectedTab = 0
    @Environment(\.colorScheme) private var colorScheme

    init(services: AppServices) {
        self.services = services
        let hasCompleted = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .bool(forKey: AppConstants.appGroupOnboardingCompletedKey) ?? false
        let needsOnboarding = !hasCompleted
        _showOnboarding = State(initialValue: needsOnboarding)
    }

    private var tabBarScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(services: services)
            }
            .tabItem {
                Label("tab_home", systemImage: "drop.fill")
            }
            .tag(0)

            NavigationStack {
                HistoryView(services: services)
            }
            .tabItem {
                Label("tab_history", systemImage: "calendar")
            }
            .tag(1)

            NavigationStack {
                SettingsView(services: services)
            }
            .tabItem {
                Label("tab_settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .scrollIndicators(.hidden)
        .toolbarColorScheme(tabBarScheme, for: .tabBar)
        .onReceive(NotificationCenter.default.publisher(for: .notificationTapped)) { _ in
            selectedTab = 0
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(services: services) {
                showOnboarding = false
            }
        }
    }
}

#Preview {
    RootView(services: AppServices(
        waterStore: PreviewWaterStore(),
        settingsStore: PreviewSettingsStore(),
        healthService: PreviewHealthService(),
        notificationService: PreviewNotificationService(),
        haptics: PreviewHapticsService(),
        liveActivity: PreviewLiveActivityService(),
        hydrationSnapshotStore: InMemoryHydrationSnapshotStore(),
        hydrationSnapshotProvider: PreviewHydrationSnapshotProvider(),
        hydrationBroadcaster: PreviewHydrationUpdateBroadcaster(),
        phoneConnectivity: nil,
        sounds: PreviewSoundService(),
        crashReporter: NoopCrashReportingService(),
        analytics: NoopAnalyticsService(),
        tipJar: PreviewTipJarService()
    ))
}
