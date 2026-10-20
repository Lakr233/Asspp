import Foundation
import ZIPFoundation

enum StorePackageValidator {
    static func validate(at url: URL, package: AppStore.AppPackage) throws {
        let archive = try Archive(url: url, accessMode: .read)
        let entries = archive.filter { StoreDownloadProtocol.isMainInfoPlist($0.path) }
        guard entries.count == 1, let entry = entries.first, entry.uncompressedSize <= 1024 * 1024 else {
            throw StoreDownloadError.invalidPackage
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard chunk.count <= 1024 * 1024 - data.count else { throw StoreDownloadError.invalidPackage }
            data.append(chunk)
        }
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw StoreDownloadError.invalidPackage
        }
        try StoreDownloadProtocol.validatePackageInfo(
            info, bundleID: package.software.bundleID,
            platform: package.entityType == .appleTV ? "AppleTVOS" : "iPhoneOS"
        )
    }
}
