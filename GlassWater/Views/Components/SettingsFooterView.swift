//
//  SettingsFooterView.swift
//  GlassWater
//

import SwiftUI

struct SettingsFooterView: View {
    let showFooter: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var heartPulse = false
    @State private var musicPulse = false
    @State private var linkTapCount = 0

    var body: some View {
        VStack(spacing: 6) {
            // "Feito com carinho" + animated heart
            HStack(spacing: 5) {
                Text("settings_footer_made_with_love")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)

                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink.opacity(0.8))
                    .scaleEffect(heartPulse ? 1.18 : 1.0)
                    .animation(
                        reduceMotion ? .none :
                            .spring(.smooth(duration: 1.2))
                            .repeatForever(autoreverses: true),
                        value: heartPulse
                    )
            }

            // "Inspirado por música" + animated music note
            HStack(spacing: 5) {
                Text("settings_footer_inspired_by_music")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)

                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundStyle(Color.cyan.opacity(0.8))
                    .scaleEffect(musicPulse ? 1.15 : 1.0)
                    .rotationEffect(.degrees(musicPulse ? 6 : -6))
                    .animation(
                        reduceMotion ? .none :
                            .spring(.smooth(duration: 1.4))
                            .repeatForever(autoreverses: true),
                        value: musicPulse
                    )
            }

            // "Prism Labs" link
            Button {
                linkTapCount += 1
                if let url = URL(string: "https://prismlabs.studio") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Prism Labs")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.onTimeOfDayTertiaryText)
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: linkTapCount)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .opacity(showFooter ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            heartPulse = true
            musicPulse = true
        }
    }
}
