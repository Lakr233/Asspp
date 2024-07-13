//
//  SettingView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import FLEX
import SwiftUI

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
                    Text("By enabling this, all your account will be redacted.")
                }
                Section {
                    Text(vm.deviceSeedAddress)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Device Seed")
                } footer: {
                    Text("This address is used to be a MAC address from your hardware to identify your device with Apple. Here we use a random one.")
                }
                Section {
                    Button("Delete All Download", role: .destructive) {
                        Downloads.this.removeAll()
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("Operating download manager.")
                }
                Section {
                    Text(ProcessInfo.processInfo.hostName)
                    Button("Open Setting") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } header: {
                    Text("Host Name")
                } footer: {
                    Text("To install app, you need to grant local area network permission in order to communicate with system services. If your host name is empty, go to Settings.app to grant permission.")
                }
                Section {
                    Button("Show FLEX") {
                        FLEXManager.shared.showExplorer()
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("FLEX is a set of in-app debugging and exploration tools for iOS development.")
                }
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
                    Text("Hope my app helps you out.")
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
            .navigationTitle("Setting")
        }
        .navigationViewStyle(.stack)
    }
}
