//
//  ProductHistoryView.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import SwiftUI

struct ProductHistoryView: View {
    @StateObject var vm: AppPackageArchive
    @State var showErrorAlert = false

    var body: some View {
        List(vm.historyPackages.keys.elements, id: \.self) { key in
            if let accountID = vm.accountID, let pkg = vm.package(for: key) {
                ProductVersionView(accountID: accountID, package: pkg)
            }
        }
        .navigationTitle("Version History")
        .navigationBarItems(trailing: trailingItems)
        .alert("Oops", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            if let error = vm.errorMessage {
                Text(error)
            }
        }
        .onChange(of: vm.errorMessage) { newValue in
            showErrorAlert = newValue != nil
        }
        .task {
            vm.lookupHistoryVersions()
        }
    }

    @ViewBuilder
    var trailingItems: some View {
        Group {
            if vm.isLoadingVersionDetails {
                ProgressView()
            }
            Button("Load More") {
                vm.loadNextPageIfNeeded()
            }
            .disabled(!vm.isLoadMoreAvailable)
        }
    }
}
