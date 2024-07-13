//
//  MainView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct MainView: View {
    @StateObject var dvm = Downloads.this

    var body: some View {
        TabView {
            WelcomeView()
                .tabItem { Label("Home", systemImage: "house") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            DownloadView()
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                        .badge(dvm.runningTaskCount)
                }
            SettingView()
                .tabItem { Label("Setting", systemImage: "gear") }
        }
    }
}
