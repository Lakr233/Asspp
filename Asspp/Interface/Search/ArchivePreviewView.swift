//
//  ArchivePreviewView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct ArchivePreviewView: View {
    let archive: AppStore.AppPackage
    var preferredIconSize: CGFloat?
    var lineLimit: Int? = 1

    private var iconSize: CGFloat {
        preferredIconSize ?? 50
    }

    private var screenScale: CGFloat {
        #if canImport(UIKit)
            UIScreen.main.scale
        #else
            NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            KFImage(URL(string: archive.software.artworkUrl))
                // Downsample the 512x512 artwork to the cell size instead of
                // decoding it at full resolution for a ~50pt icon.
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: iconSize, height: iconSize)))
                .scaleFactor(screenScale)
                .cacheOriginalImage()
                .antialiased(true)
                .resizable()
                .clipShape(.rect(cornerRadius: 0.2184466 * iconSize))
                .frame(width: iconSize, height: iconSize, alignment: .center)
                .shadow(radius: 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(archive.software.name)
                        .bold()
                        .lineLimit(2)
                    Spacer()
                    Text(archive.software.version)
                        .foregroundStyle(.secondary)
                }
                Text(archive.software.sellerName)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
