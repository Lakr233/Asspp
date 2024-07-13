//
//  PackageView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct PackageView: View {
    let request: Downloads.Request
    var archive: iTunesResponse.iTunesArchive {
        request.package
    }

    var url: URL { request.targetLocation }

    @Environment(\.dismiss) var dismiss
    @State var installer: Installer?
    @State var error: String = ""

    @StateObject var vm = AppStore.this

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    KFImage(URL(string: archive.artworkUrl512 ?? ""))
                        .antialiased(true)
                        .resizable()
                        .cornerRadius(8)
                        .frame(width: 50, height: 50, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(archive.name)
                        .bold()
                }
                .padding(.vertical, 4)
            } header: {
                Text("Package")
            } footer: {
                Text("\(archive.bundleIdentifier) - \(archive.version) - \(archive.byteCountDescription)")
            }

            if Downloads.this.isCompleted(for: request) {
                Section {
                    Button("Install") {
                        do {
                            installer = try Installer(archive: archive, path: url)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .sheet(item: $installer) {
                        installer?.destroy()
                        installer = nil
                    } content: {
                        InstallerView(installer: $0)
                    }

                    Button("Install via AirDrop") {
                        let newUrl = temporaryDirectory
                            .appendingPathComponent("\(archive.bundleIdentifier)-\(archive.version)")
                            .appendingPathExtension("ipa")
                        try? FileManager.default.removeItem(at: newUrl)
                        try? FileManager.default.copyItem(at: url, to: newUrl)
                        share(items: [newUrl])
                    }
                } header: {
                    Text("Control")
                } footer: {
                    if error.isEmpty {
                        Text("Direct install may have limitations that is not able to bypass. Use AirDrop method if possible on another device.")
                    } else {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Section {
                    switch request.runtime.status {
                    case .stopped:
                        Button("Continue Download") {
                            Downloads.this.resume(requestID: request.id)
                        }
                    case .downloading,
                         .pending:
                        Text("Download In Progress...")
                    case .verifying:
                        Text("Verification In Progress...")
                    case .completed:
                        Group {}
                    }
                } header: {
                    Text("Incomplete Package")
                } footer: {
                    switch request.runtime.status {
                    case .stopped:
                        Text("Either connection is lost or the download is interrupted. Tap to continue.")
                    case .downloading,
                         .pending:
                        Text("\(Int(request.runtime.percent * 100))%...")
                    case .verifying:
                        Text("\(Int(request.runtime.percent * 100))%...")
                    case .completed:
                        Group {}
                    }
                }
            }

            Section {
                if vm.demoMode {
                    Text("88888888888")
                        .redacted(reason: .placeholder)
                } else {
                    Text(request.account.email)
                }
                Text("\(request.account.countryCode) - \(ApplePackage.countryCodeMap[request.account.countryCode] ?? "-1")")
            } header: {
                Text("Account")
            } footer: {
                Text("This account is used to download this package. If you choose to AirDrop, your target device must sign in or previously signed in to this account and have at least one app installed.")
            }

            Section {
                Button("Delete") {
                    Downloads.this.delete(request: request)
                    dismiss()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text(url.path)
            }
        }
        .navigationTitle(request.package.name)
    }

    @discardableResult
    func share(
        items: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil
    ) -> Bool {
        guard let source = UIWindow.mainWindow?.rootViewController?.topMostController else {
            return false
        }
        let newView = UIView()
        source.view.addSubview(newView)
        newView.frame = .init(origin: .zero, size: .init(width: 10, height: 10))
        newView.center = .init(
            x: source.view.bounds.width / 2 - 5,
            y: source.view.bounds.height / 2 - 5
        )
        let vc = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        vc.excludedActivityTypes = excludedActivityTypes
        vc.popoverPresentationController?.sourceView = source.view
        vc.popoverPresentationController?.sourceRect = newView.frame
        source.present(vc, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                newView.removeFromSuperview()
            }
        }
        return true
    }
}

extension UIWindow {
    static var mainWindow: UIWindow? {
        if let keyWindow = UIApplication
            .shared
            .value(forKey: "keyWindow") as? UIWindow
        {
            return keyWindow
        }
        // if apple remove this shit, we fall back to ugly solution
        let keyWindow = UIApplication
            .shared
            .connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .filter(\.isKeyWindow)
            .first
        return keyWindow
    }
}

extension UIViewController {
    var topMostController: UIViewController? {
        var result: UIViewController? = self
        while true {
            if let next = result?.presentedViewController,
               !next.isBeingDismissed,
               next as? UISearchController == nil
            {
                result = next
                continue
            }
            if let tabBar = result as? UITabBarController,
               let next = tabBar.selectedViewController
            {
                result = next
                continue
            }
            if let split = result as? UISplitViewController,
               let next = split.viewControllers.last
            {
                result = next
                continue
            }
            if let navigator = result as? UINavigationController,
               let next = navigator.viewControllers.last
            {
                result = next
                continue
            }
            break
        }
        return result
    }
}
