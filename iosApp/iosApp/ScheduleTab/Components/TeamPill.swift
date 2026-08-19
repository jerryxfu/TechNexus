//
//  TeamPill.swift
//  iosApp
//
//  Created by Jerry Fu on 2026-04-10.
//

import SwiftUI

struct TeamPill: View {
    let team: String
    let color: Color
    let compact: Bool
    let highlight: Color?

    var body: some View {
        let fontSize: CGFloat = compact ? 11 : 12
        let hPad: CGFloat = compact ? 5 : 6
        let vPad: CGFloat = compact ? 2 : 3

        Text(team)
            .font(
                .system(
                    size: fontSize,
                    weight: highlight != nil ? .bold : .medium
                )
            )
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            // Only the unhighlighted values moved. The highlighted ones are
            // what a pill is measured against, so raising both would have kept
            // the gap the same and gained nothing.
            .background(
                (highlight ?? color).opacity(highlight != nil ? 0.25 : 0.11)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        (highlight ?? color).opacity(
                            highlight != nil ? 0.6 : 0.32
                        ),
                        lineWidth: highlight != nil ? 1.5 : 0.5
                    )
            )
    }
}
