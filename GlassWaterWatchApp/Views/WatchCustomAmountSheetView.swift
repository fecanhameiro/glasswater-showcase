//
//  WatchCustomAmountSheetView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

// MARK: - Custom Amount Sheet

struct WatchCustomAmountSheetView: View {
    @Binding var selection: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Crown value mapped to step index (1 = 50ml, 2 = 100ml, ..., 30 = 1500ml)
    @State private var crownValue: Double
    @State private var animatedFillProgress: Double = 0.1
    @State private var amplitudeBoost: CGFloat = 0
    @State private var lastCrownChangeTime: Date = .now
    @FocusState private var isCrownFocused: Bool

    private static let stepSize = AppConstants.customAmountStepMl
    private static let minStep = Double(AppConstants.customAmountMinMl / stepSize)   // 1
    private static let maxStep = Double(AppConstants.customAmountMaxMl / stepSize)   // 30

    private static func mlToStep(_ ml: Int) -> Double {
        Double(ml / stepSize)
    }

    private static func stepToMl(_ step: Double) -> Int {
        Int(step.rounded()) * stepSize
    }

    init(selection: Binding<Int>, onSave: @escaping (Int) -> Void) {
        self._selection = selection
        self.onSave = onSave
        self._crownValue = State(initialValue: Self.mlToStep(selection.wrappedValue))
    }

    private var formattedSelection: String {
        VolumeFormatters.string(fromMl: selection, unitStyle: .short)
    }

    private var fillProgress: Double {
        let range = Double(AppConstants.customAmountMaxMl - AppConstants.customAmountMinMl)
        guard range > 0 else { return 0.1 }
        let raw = Double(selection - AppConstants.customAmountMinMl) / range
        // 10% min fill so water is always visible, 95% max
        return 0.10 + raw * 0.85
    }

    var body: some View {
        ZStack {
            // Dark base gradient (visible above water line)
            WatchGradientBackground()
                .ignoresSafeArea()

            // Rising water controlled by Digital Crown
            WatchWaterFillBackground(progress: animatedFillProgress, amplitudeBoost: amplitudeBoost)
                .ignoresSafeArea()

            // Content overlay — crown modifiers attached here
            VStack(spacing: 6) {
                Spacer()

                // Amount display — centered above water surface
                Text(formattedSelection)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(.snappy), value: selection)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                Spacer()

                // Min / Max range labels
                HStack {
                    Text(VolumeFormatters.string(fromMl: AppConstants.customAmountMinMl, unitStyle: .short))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Text(VolumeFormatters.string(fromMl: AppConstants.customAmountMaxMl, unitStyle: .short))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                Spacer(minLength: 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(formattedSelection))
            .accessibilityHint(Text("watch_accessibility_crown_hint"))
            .focusable()
            .focused($isCrownFocused)
            .digitalCrownRotation(
                $crownValue,
                from: Self.minStep,
                through: Self.maxStep,
                by: 1.0,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
        }
        .scrollDisabled(true)
        .onChange(of: crownValue) { _, newValue in
            let ml = Self.stepToMl(newValue)
            let clamped = QuickAddOptions.clampCustomAmount(ml)
            guard clamped != selection else { return }
            selection = clamped

            // Smooth water level transition
            withAnimation(.spring(.smooth(duration: 0.35))) {
                animatedFillProgress = fillProgress
            }

            // Crown momentum: detect fast spinning → slosh effect
            let now = Date()
            let delta = now.timeIntervalSince(lastCrownChangeTime)
            lastCrownChangeTime = now
            if delta < 0.15 {
                amplitudeBoost = 1.0
                withAnimation(.spring(.smooth(duration: 0.8))) {
                    amplitudeBoost = 0
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let clamped = QuickAddOptions.clampCustomAmount(selection)
                selection = clamped
                onSave(clamped)
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("common_done")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.3), Color.cyan.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .onAppear {
            let clamped = QuickAddOptions.clampCustomAmount(selection)
            selection = clamped
            crownValue = Self.mlToStep(clamped)
            animatedFillProgress = fillProgress
            isCrownFocused = true
        }
    }
}
