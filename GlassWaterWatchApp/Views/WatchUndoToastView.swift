//
//  WatchUndoToastView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

/// Floating undo button with a circular countdown ring.
/// The ring depletes over the duration, then the ViewModel dismisses it.
struct WatchUndoToastView: View {
    let onUndo: () -> Void
    let duration: TimeInterval

    @State private var ringProgress: Double = 1.0

    var body: some View {
        Button(action: onUndo) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.cyan.opacity(0.15), lineWidth: 2.5)

                // Countdown ring
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        Color.cyan.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Undo icon
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color.cyan.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(.smooth(duration: duration, extraBounce: 0))) {
                ringProgress = 0
            }
        }
    }
}
