//
//  AddAccountView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

struct AddAccountView: View {
    @StateObject var vm = AppStore.this
    @Environment(\.dismiss) var dismiss

    @State var email: String = ""
    @State var password: String = ""
    @State var isPasswordHidden = true

    @State var codeRequired: Bool = false
    @State var code: String = ""

    @State var error: Error?
    @State var openProgress: Bool = false

    var body: some View {
        List {
            Section {
                TextField("Email (Apple ID)", text: $email)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                if isPasswordHidden {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } else {
                    TextField("Password", text: $password)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .font(.system(.footnote, design: .monospaced))
                }
            } header: {
                HStack {
                    Text("Apple ID")
                    Spacer()
                    Button(isPasswordHidden ? "Show Password" : "Hide Password") {
                        isPasswordHidden.toggle()
                    }
                    .disabled(password.isEmpty)
                }
            } footer: {
                Text("Your account is saved in your Keychain and will be synced across devices with the same iCloud account signed in.")
            }
            if codeRequired {
                Section {
                    TextField("2FA Code (Optional)", text: $code)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .keyboardType(.numberPad)
                } header: {
                    Text("2FA Code")
                } footer: {
                    Text("Although the 2FA code is marked as optional, it's because we don't know if you have it enabled or just entered an incorrect password. Provide it if you have 2FA enabled.\n\nhttps://support.apple.com/102606")
                }
                .transition(.opacity)
            }
            Section {
                if openProgress {
                    ForEach([UUID()], id: \.self) { _ in
                        ProgressView()
                    }
                } else {
                    Button("Authenticate") {
                        authenticate()
                    }
                    .disabled(openProgress)
                    .disabled(email.isEmpty || password.isEmpty)
                }
            } footer: {
                if let error {
                    Text(error.localizedDescription)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring, value: codeRequired)
        .listStyle(.insetGrouped)
        .navigationTitle("Add Account")
    }

    func authenticate() {
        openProgress = true
        Task {
            defer { DispatchQueue.main.async { openProgress = false } }
            do {
                _ = try await vm.authenticate(email: email, password: password, code: code.isEmpty ? "" : code)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    codeRequired = true
                }
            }
        }
    }
}
