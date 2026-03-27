//
//  WatchHistoryView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchHistoryView: View {
    @Bindable var viewModel: WatchHomeViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                WatchGradientBackground()

                if viewModel.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        WatchEntriesListView(entries: viewModel.entries)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(Text("watch_entries_title"))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.watchWaterCyan.opacity(0.5))

            Text("watch_entries_empty")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.watchTextSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
