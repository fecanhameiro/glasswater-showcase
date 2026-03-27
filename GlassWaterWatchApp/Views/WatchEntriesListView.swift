//
//  WatchEntriesListView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchEntriesListView: View {
    let entries: [WatchStateEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    WatchEntryRow(entry: entry)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    if index < entries.count - 1 {
                        Divider()
                            .background(Color.watchCardBorder)
                            .padding(.leading, 28)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.watchCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.watchCardBorder, lineWidth: 0.5)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
