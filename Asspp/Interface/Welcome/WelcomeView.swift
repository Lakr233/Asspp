//
//  WelcomeView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ColorfulX
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Image(.avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                Text("Welcome to Asspp")
                    .font(.system(.headline, design: .rounded))
                inst
                    .font(.system(.footnote, design: .rounded))
                    .padding(.horizontal, 32)
                Spacer().frame(height: 0)
            }

            VStack(spacing: 16) {
                Spacer()
                Text(appVersion)
                Text("App Store itself is unstable, retry if needed.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ColorfulView(color: .constant(ColorfulPreset.winter.colors))
                .opacity(0.25)
                .ignoresSafeArea()
        )
    }

    var inst: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "1.circle.fill")
                Text("Sign in to your account.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "2.circle.fill")
                Text("Search for apps you want to install.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "3.circle.fill")
                Text("Download and save the ipa file.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "4.circle.fill")
                Text("Install or AirDrop to install.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
