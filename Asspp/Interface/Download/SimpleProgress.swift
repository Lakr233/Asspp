//
//  SimpleProgress.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import SwiftUI

struct SimpleProgress: View {
    let progress: Progress
    var body: some View {
        Rectangle()
            .foregroundStyle(.gray)
            .overlay {
                GeometryReader { r in
                    Rectangle()
                        .foregroundStyle(.accent)
                        .frame(width: CGFloat(progress.fractionCompleted) * r.size.width)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
