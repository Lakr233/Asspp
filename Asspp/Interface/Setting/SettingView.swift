//
//  SettingView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct SettingView: View {
    @StateObject var vm = AppStore.this

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Demo Mode", isOn: $vm.demoMode)
                } header: {
                    Text("Demo Mode")
                } footer: {
                    Text("By enabling this, all your accounts will be redacted.")
                }
                Section {
                    Button("Delete All Downloads", role: .destructive) {
                        Downloads.this.removeAll()
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("Manage downloads.")
                }
                Section {
                    Text(ProcessInfo.processInfo.hostName)
                    Text(ApplePackage.Configuration.deviceIdentifier)
                        .font(.system(.body, design: .monospaced))
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } header: {
                    Text("Host Name")
                } footer: {
                    Text("Grant local network permission to install apps and communicate with system services. If hostname is empty, open Settings to grant permission.")
                }

                #if canImport(UIKit)
                    Section {
                        Button("Install Certificate") {
                            UIApplication.shared.open(Installer.caURL)
                        }
                    } header: {
                        Text("SSL")
                    } footer: {
                        Text("On device installer requires your system to trust a self signed certificate. Tap the button to install it. After install, navigate to Settings > General > About > Certificate Trust Settings and enable full trust for the certificate.")
                    }
                #endif

                Section {
                    Button("@Lakr233") {
                        UIApplication.shared.open(URL(string: "https://twitter.com/Lakr233")!)
                    }
                    Button("Buy me a coffee! ☕️") {
                        UIApplication.shared.open(URL(string: "https://github.com/sponsors/Lakr233/")!)
                    }
                    Button("Feedback & Contact") {
                        UIApplication.shared.open(URL(string: "https://github.com/Lakr233/Asspp")!)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Hope this app helps you!")
                }
                Section {
                    Button("Reset", role: .destructive) {
                        try? FileManager.default.removeItem(at: documentsDirectory)
                        try? FileManager.default.removeItem(at: temporaryDirectory)
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            exit(0)
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will reset all your settings.")
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}
