//
//  InstallerView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct InstallerView: View {
    @StateObject var installer: Installer

    var icon: String {
        switch installer.status {
        case .ready:
            "app.gift"
        case .sendingManifest:
            "paperplane.fill"
        case .sendingPayload:
            "paperplane.fill"
        case let .completed(result):
            switch result {
            case .success:
                "app.badge.checkmark"
            case .failure:
                "exclamationmark.triangle.fill"
            }
        case .broken:
            "exclamationmark.triangle.fill"
        }
    }

    var text: String {
        switch installer.status {
        case .ready: NSLocalizedString("Ready To Install", comment: "")
        case .sendingManifest: NSLocalizedString("Sending Manifest...", comment: "")
        case .sendingPayload: NSLocalizedString("Sending Payload...", comment: "")
        case let .completed(result):
            switch result {
            case .success:
                NSLocalizedString("Install Completed", comment: "")
            case let .failure(failure):
                failure.localizedDescription
            }
        case let .broken(error):
            error.localizedDescription
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                ForEach([icon], id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(.largeTitle, design: .rounded))
                        .transition(.opacity.combined(with: .scale))
                }
                ForEach([text], id: \.self) { text in
                    Text(text)
                        .font(.system(.body, design: .rounded))
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if case .ready = installer.status {
                    UIApplication.shared.open(installer.iTunesLink)
                }
            }
            .onAppear {
                if case .ready = installer.status {
                    UIApplication.shared.open(installer.iTunesLink)
                }
            }
            VStack {
                Text("To install app, you need to grant local area network permission in order to communicate with system services.")
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(32)
        }
        .animation(.spring, value: text)
        .animation(.spring, value: icon)
        .onDisappear {
            installer.destroy()
        }
    }
}
