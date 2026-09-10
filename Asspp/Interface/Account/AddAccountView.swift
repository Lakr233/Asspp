//
//  AddAccountView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import ButtonKit
import SwiftUI

struct AddAccountView: View {
    @State private var vm = AppStore.this
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordHidden = true

    @State private var codeRequired: Bool = false
    @State private var code: String = ""

    @State private var error: Error?

    var body: some View {
        Form {
            Section {
                TextField("Email (Apple ID)", text: $email)
                #if os(iOS)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                #endif
                if isPasswordHidden {
                    SecureField("Password", text: $password)
                    #if os(iOS)
                        .textContentType(.password)
                    #endif
                } else {
                    TextField(text: $password) {
                        Text("Password")
                            .font(.body)
                    }
                    #if os(iOS)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.password)
                    #endif
                    .font(.body.monospaced())
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
                    TextField("Verification Code", text: $code)
                    #if os(iOS)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    #endif
                } header: {
                    Text("2FA Code")
                } footer: {
                    Text("Enter the six-digit verification code from your trusted Apple device.")
                }
                .transition(.opacity)
            }
            Section {
                AsyncButton {
                    self.error = nil
                    do {
                        _ = try await vm.authenticate(email: email, password: password, code: code.isEmpty ? "" : code)
                        dismiss()
                    } catch {
                        self.error = error
                        codeRequired = codeRequired || (error as? StoreAuthenticationError)?.needsCode == true
                        throw error
                    }
                } label: {
                    Text("Authenticate")
                }
                .disabledWhenLoading()
                .disabled(email.isEmpty || password.isEmpty)
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
        .formStyle(.grouped)
        .animation(.spring, value: codeRequired)
        #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .navigationTitle("Add Account")
    }
}
