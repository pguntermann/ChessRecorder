//
//  ToolbarIconLabel.swift
//  Chess Recorder
//

import SwiftUI

enum ToolbarMetrics {
    static func iconHitSize(compact: Bool, availableWidth: CGFloat) -> CGFloat {
        let isNarrowPortrait = compact && availableWidth < 500
        let isNarrowSidebar = !compact && availableWidth < 400
        if isNarrowPortrait || isNarrowSidebar {
            return 36
        }
        return compact ? 40 : 44
    }
}

struct ToolbarIconLabel: View {
    let systemName: String
    var hitSize: CGFloat = 44

    init(_ systemName: String, hitSize: CGFloat = 44) {
        self.systemName = systemName
        self.hitSize = hitSize
    }

    var body: some View {
        Image(systemName: systemName)
            .imageScale(.medium)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
    }
}
