//
//  WatchLayoutMetrics.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchLayoutMetrics {
    let screenWidth: CGFloat

    /// Scale factor relative to 46mm watch (198pt width)
    private var scale: CGFloat { screenWidth / 198 }

    // MARK: - Ring

    var ringDiameter: CGFloat { round(64 * scale) }
    var ringStroke: CGFloat { max(round(6 * scale), 4) }
    var ringGlowSize: CGFloat { round(88 * scale) }
    var ringGlowStartRadius: CGFloat { round(26 * scale) }
    var ringGlowEndRadius: CGFloat { round(44 * scale) }

    // MARK: - Card

    var cardVerticalPadding: CGFloat { round(8 * scale) }
    var cardHorizontalPadding: CGFloat { round(8 * scale) }
    var cardCornerRadius: CGFloat { round(16 * scale) }
    var cardSpacing: CGFloat { round(6 * scale) }

    // MARK: - Layout

    var mainSpacing: CGFloat { round(10 * scale) }
    var scrollHorizontalPadding: CGFloat { round(8 * scale) }
    var scrollVerticalPadding: CGFloat { round(8 * scale) }

    // MARK: - Buttons

    var buttonSpacing: CGFloat { round(8 * scale) }
    var buttonVerticalPadding: CGFloat { round(10 * scale) }

    // MARK: - Always-On Display

    var aodRingSize: CGFloat { round(80 * scale) }
    var aodStroke: CGFloat { max(round(6 * scale), 4) }
}
