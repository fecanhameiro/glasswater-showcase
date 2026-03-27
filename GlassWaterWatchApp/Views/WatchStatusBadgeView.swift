//
//  WatchStatusBadgeView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchStatusBadgeView: View {
    let progress: Double
    let goalReached: Bool

    private var statusMessage: String {
        if goalReached {
            return Localized.string("watch_status_complete")
        } else if progress >= 0.75 {
            return Localized.string("watch_status_almost")
        } else if progress >= 0.5 {
            return Localized.string("watch_status_halfway")
        } else if progress > 0 {
            return Localized.string("watch_status_keep_going")
        } else {
            return Localized.string("watch_status_start")
        }
    }

    private var statusIcon: String {
        if goalReached { return "checkmark.circle.fill" }
        if progress >= 0.75 { return "flame.fill" }
        if progress >= 0.5 { return "bolt.fill" }
        return "drop.fill"
    }

    private var statusColor: Color {
        if goalReached { return .watchStatusSuccess }
        if progress >= 0.75 { return .watchStatusWarning }
        return .watchStatusCyan
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(statusMessage)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.2))
        )
        .contentTransition(.opacity)
        .animation(.spring(.bouncy(duration: 0.25)), value: goalReached)
        .animation(.spring(.bouncy(duration: 0.25)), value: statusMessage)
        .accessibilityLabel(Text(statusMessage))
    }
}
