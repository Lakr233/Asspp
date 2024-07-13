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
                SecureField("Password", text: $password)
            } header: {
                Text("ID")
            } footer: {
                Text("We will store your account and password on disk without encryption. Please do not connect your device to untrusted hardware or use this app on a open system like macOS.")
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
                    Text("Although 2FA code is marked as optional, that is because we dont know if you have it or just incorrect password, you should provide it if you have it enabled.\n\nhttps://support.apple.com/102606")
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
        DispatchQueue.global().async {
            defer { DispatchQueue.main.async { openProgress = false } }
            let auth = ApplePackage.Authenticator(email: email)
            do {
                let account = try auth.authenticate(password: password, code: code.isEmpty ? nil : code)
                DispatchQueue.main.async {
                    vm.save(email: email, password: password, account: account)
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    codeRequired = true
                }
            }
        }
    }
}
