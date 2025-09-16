//
//  PackageDisplayView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct PackageDisplayView: View {
    let archive: AppStore.AppPackage
    @State var style: DisplayStyle = .compact

    enum DisplayStyle {
        case compact
        case detail
    }

    var body: some View {
        _body
            .overlay(alignment: .bottomTrailing) {
                if style != .detail {
                    Button {
                        style = .detail
                    } label: {
                        Text("more")
                            .font(.system(.footnote, design: .rounded))
                            .padding(.leading, 10)
                    }
                    .background(LinearGradient(
                        gradient: Gradient(colors: [.clear, .white]),
                        startPoint: .init(x: 0, y: 0.5),
                        endPoint: .init(x: 0.2, y: 0.5)
                    ).blendMode(.destinationOut))
                    .transition(.scale)
                }
            }
            .compositingGroup()
            .padding(.vertical, 4)
    }

    @ViewBuilder
    var _body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KFImage(URL(string: archive.software.artworkUrl))
                .antialiased(true)
                .resizable()
                .cornerRadius(8)
                .frame(width: 50, height: 50, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(archive.software.name)
                .bold()
            if !archive.software.description.isEmpty {
                Group {
                    switch style {
                    case .compact:
                        Text(archive.software.description)
                            .lineLimit(3)
                    case .detail:
                        Text(archive.software.description)
                    }
                }
                .font(.system(.footnote, design: .rounded))
            }
        }
    }
}
