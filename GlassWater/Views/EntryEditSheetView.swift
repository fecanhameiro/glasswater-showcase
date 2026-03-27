//
//  EntryEditSheetView.swift
//  GlassWater
//

import SwiftUI

struct EntryEditSheetView: View {
    let entry: WaterEntry
    let onSave: (Int, Date) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var amountMl: Int
    @State private var date: Date
    @State private var hasAppeared = false
    @State private var dropPulse = false
    @State private var textFloat = false
    @State private var confirmingDelete = false
    @State private var lightHapticTrigger = false
    @State private var warningHapticTrigger = false
    @State private var successHapticTrigger = false

    init(entry: WaterEntry, onSave: @escaping (Int, Date) -> Void, onDelete: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        _amountMl = State(initialValue: entry.amountMl)
        _date = State(initialValue: entry.date)
    }

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: amountMl, unitStyle: .short)
    }

    private var hasChanges: Bool {
        amountMl != entry.amountMl || date != entry.date
    }

    private var primaryTextColor: Color {
        Color.onTimeOfDayText
    }

    private var secondaryTextColor: Color {
        Color.onTimeOfDaySecondaryText
    }

    private var toolbarScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }

    private var amountStepMl: Int {
        QuickAddOptions.stepMlForCurrentUnit(metricStepMl: 50)
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TimeOfDayBackgroundView()

                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle("home_entry_edit_title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(toolbarScheme, for: .navigationBar)
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
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text("common_back"))
                    }
                }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                // Slight delay to let sheet settle, then animate content
                Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    hasAppeared = true
                }
                // Start continuous animations after content appears
                if !reduceMotion {
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        withAnimation(.spring(.smooth(duration: 2.5)).repeatForever(autoreverses: true)) {
                            dropPulse = true
                        }
                        // Floating text animation (slightly offset timing for organic feel)
                        textFloat = true
                    }
                }
            }
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            heroSection
                .padding(.top, 8)

            Spacer()
                .frame(height: 24)

            amountControlsSection

            Spacer()
                .frame(height: 20)

            timeSection

            Spacer()
                .frame(minHeight: 16, maxHeight: 32)

            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 16)
        }
    }

    // MARK: - Landscape Layout

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left side: drop icon + amount
            VStack(spacing: 8) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.waterDrop.opacity(0.2), Color.waterDrop.opacity(0.06), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 36
                            )
                        )
                        .frame(width: 72, height: 72)
                        .scaleEffect(dropPulse ? 1.06 : 0.98)

                    Image(systemName: "drop.fill")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.waterGradientStart, Color.waterDrop, Color.waterGradientEnd],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.waterDrop.opacity(0.5), radius: 8, y: 2)
                }
                .frame(width: 80, height: 80)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.9)
                .animation(reduceMotion ? .none : .spring(.smooth), value: hasAppeared)

                Text(formattedAmount)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(LinearGradient.waterGradient)
                    .contentTransition(.numericText())
                    .animation(.spring(.bouncy), value: amountMl)

                amountControlsSection

                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Right side: time + action bar
            VStack(spacing: 12) {
                Spacer()

                timeSection

                actionBar

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Animated Water Drop - contained in fixed frame
            ZStack {
                // Outer glow ring (contained, won't overflow)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.waterDrop.opacity(0.2),
                                Color.waterDrop.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(dropPulse ? 1.06 : 0.98)

                // Inner glow
                Circle()
                    .fill(Color.waterDrop.opacity(0.12))
                    .frame(width: 70, height: 70)
                    .scaleEffect(dropPulse ? 1.03 : 1.0)

                // Water drop icon
                Image(systemName: "drop.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.waterGradientStart, Color.waterDrop, Color.waterGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.waterDrop.opacity(0.5), radius: 10, y: 3)
            }
            .frame(width: 110, height: 110)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .animation(reduceMotion ? .none : .spring(.smooth), value: hasAppeared)

            // Amount Display with floating animation
            ZStack {
                Text(formattedAmount)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(LinearGradient.waterGradient)
                    .shadow(color: Color.waterDrop.opacity(textFloat ? 0.4 : 0.25), radius: textFloat ? 12 : 8, y: 2)
                    .contentTransition(.numericText())
                    .animation(.spring(.bouncy), value: amountMl)
                    .offset(y: textFloat ? -3 : 3)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.95)
                    .animation(reduceMotion ? .none : .spring(.smooth).delay(0.05), value: hasAppeared)
                    .animation(reduceMotion ? .none : .spring(.smooth(duration: 2.0)).repeatForever(autoreverses: true), value: textFloat)
            }
            .frame(height: 64)
        }
        .padding(.vertical, 8) // Extra padding to prevent clipping during float
    }

    // MARK: - Amount Controls Section

    private var amountControlsSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 40) {
                // Decrease button
                Button {
                    if amountMl > 50 {
                        withAnimation(.spring(.bouncy)) {
                            amountMl = max(50, amountMl - amountStepMl)
                        }
                        lightHapticTrigger.toggle()
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 60, height: 60)
                }
                .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .circle)
                .glassEffectID("decrease", in: glassNamespace)
                .opacity(amountMl <= 50 ? 0.4 : 1.0)

                // Increase button
                Button {
                    if amountMl < 4000 {
                        withAnimation(.spring(.bouncy)) {
                            amountMl = min(4000, amountMl + amountStepMl)
                        }
                        lightHapticTrigger.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 60, height: 60)
                }
                .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .circle)
                .glassEffectID("increase", in: glassNamespace)
                .opacity(amountMl >= 4000 ? 0.4 : 1.0)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.95)
        .animation(reduceMotion ? .none : .spring(.smooth).delay(0.08), value: hasAppeared)
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(spacing: 8) {
            // Section label
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.caption.weight(.medium))
                Text("entries_edit_time")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(secondaryTextColor)

            // Date picker in glass container
            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .environment(\.colorScheme, toolbarScheme)
            .accessibilityLabel(Text("entries_edit_time"))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .sensoryFeedback(.selection, trigger: date)
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.95)
        .animation(reduceMotion ? .none : .spring(.smooth).delay(0.12), value: hasAppeared)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 24) {
                // Delete button with inline confirmation
                Button {
                    if confirmingDelete {
                        // Second tap - confirm delete
                        warningHapticTrigger.toggle()
                        onDelete()
                        dismiss()
                    } else {
                        // First tap - show confirmation state
                        lightHapticTrigger.toggle()
                        withAnimation(.spring(.bouncy)) {
                            confirmingDelete = true
                        }
                        // Auto-reset after 3 seconds if not confirmed
                        Task {
                            try? await Task.sleep(for: .seconds(3.0))
                            withAnimation(.spring(.smooth)) {
                                confirmingDelete = false
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: confirmingDelete ? "trash.fill" : "trash")
                            .font(.title3.weight(.semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(confirmingDelete ? "entries_delete_confirm" : "entries_edit_delete")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(confirmingDelete ? .white : .red)
                    .frame(width: 70, height: 70)
                }
                .glassEffect(
                    .regular.tint(confirmingDelete ? Color.red.opacity(0.6) : Color.red.opacity(0.1)).interactive(),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .glassEffectID("delete", in: glassNamespace)
                .scaleEffect(confirmingDelete ? 1.05 : 1.0)

                // Save button
                Button {
                    successHapticTrigger.toggle()
                    onSave(amountMl, date)
                    dismiss()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                        Text("common_save")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(hasChanges ? .green : primaryTextColor.opacity(0.4))
                    .frame(width: 70, height: 70)
                }
                .glassEffect(
                    .regular.tint(hasChanges ? Color.green.opacity(0.15) : Color.clear).interactive(),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .glassEffectID("save", in: glassNamespace)
                .opacity(hasChanges ? 1.0 : 0.5)
                .scaleEffect(hasChanges ? 1.0 : 0.95)
                .animation(.spring(.bouncy), value: hasChanges)
                .disabled(!hasChanges)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.95)
        .animation(reduceMotion ? .none : .spring(.smooth).delay(0.16), value: hasAppeared)
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTrigger)
        .sensoryFeedback(.warning, trigger: warningHapticTrigger)
        .sensoryFeedback(.success, trigger: successHapticTrigger)
        .animation(.spring(.bouncy), value: confirmingDelete)
    }
}
