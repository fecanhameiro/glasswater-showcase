//
//  WatchEntryRow.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchEntryRow: View {
    let entry: WatchStateEntry

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: entry.amountMl, unitStyle: .short)
    }

    private var formattedTime: String {
        entry.date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.watchWaterCyan)

            Text(formattedAmount)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.watchTextPrimary)

            Spacer()

            Text(formattedTime)
                .font(.system(size: 11))
                .foregroundStyle(Color.watchTextTertiary)
        }
        .padding(.vertical, 3)
    }
}
