//
//  CustomAmountSheetView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI

struct CustomAmountSheetView: View {
    @Binding var selection: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var hasAppeared = false
    @State private var dropPulse = false
    @State private var hapticTrigger = 0
    @State private var confirmTrigger = 0

    private var formattedSelection: String {
        VolumeFormatters.string(fromMl: selection, unitStyle: .short)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var customStepMl: Int {
        QuickAddOptions.stepMlForCurrentUnit(metricStepMl: AppConstants.customAmountStepMl)
    }

    var body: some View {
        NavigationStack {
            customAmountContent
                .navigationTitle("home_custom_amount_title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(primaryTextColor)
                                .frame(width: 36, height: 36)
                        }
                        .glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive(), in: .circle)
                        .accessibilityLabel(Text("common_back"))
                    }
                }
        }
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            selection = QuickAddOptions.clampCustomAmount(selection)
            Task {
                try? await Task.sleep(for: .seconds(0.15))
                hasAppeared = true
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(.spring(.smooth(duration: 2.5)).repeatForever(autoreverses: true)) {
                        dropPulse = true
                    }
                }
            }
        }
        .onDisappear {
            dropPulse = false
        }
    }

    private var customAmountContent: some View {
        VStack(spacing: 24) {
            // Hero Section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.waterDrop.opacity(0.2), Color.waterDrop.opacity(0.06), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 44
                            )
                        )
                        .frame(width: 88, height: 88)
                        .scaleEffect(dropPulse ? 1.05 : 0.98)

                    Image(systemName: "drop.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.waterGradientStart, Color.waterDrop, Color.waterGradientEnd],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.waterDrop.opacity(0.4), radius: 8, y: 3)
                }
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.9)
                .animation(reduceMotion ? .none : .spring(.smooth), value: hasAppeared)

                Text(formattedSelection)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.waterGradient)
                    .contentTransition(.numericText())
                    .animation(.spring(.bouncy), value: selection)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.95)
                    .animation(reduceMotion ? .none : .spring(.smooth).delay(0.05), value: hasAppeared)
            }

            // +/- Controls
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 40) {
                    Button {
                        if selection > AppConstants.customAmountMinMl {
                            withAnimation(.spring(.bouncy)) {
                                selection = max(AppConstants.customAmountMinMl, selection - customStepMl)
                            }
                            hapticTrigger += 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(primaryTextColor)
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .circle)
                    .glassEffectID("decrease", in: glassNamespace)
                    .opacity(selection <= AppConstants.customAmountMinMl ? 0.4 : 1.0)

                    Button {
                        if selection < AppConstants.customAmountMaxMl {
                            withAnimation(.spring(.bouncy)) {
                                selection = min(AppConstants.customAmountMaxMl, selection + customStepMl)
                            }
                            hapticTrigger += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(primaryTextColor)
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .circle)
                    .glassEffectID("increase", in: glassNamespace)
                    .opacity(selection >= AppConstants.customAmountMaxMl ? 0.4 : 1.0)
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.95)
            .animation(reduceMotion ? .none : .spring(.smooth).delay(0.08), value: hasAppeared)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .safeAreaInset(edge: .bottom) {
            Button {
                confirmTrigger += 1
                let clamped = QuickAddOptions.clampCustomAmount(selection)
                selection = clamped
                onSave(clamped)
                dismiss()
            } label: {
                Text("common_done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .glassEffect(
                .regular.tint(Color.cyan.opacity(0.25)).interactive(),
                in: .capsule
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.95)
            .animation(reduceMotion ? .none : .spring(.smooth).delay(0.12), value: hasAppeared)
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmTrigger)
    }
}
