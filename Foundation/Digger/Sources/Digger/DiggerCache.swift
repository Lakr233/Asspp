//
//  DiggerCache.swift
//  Digger
//
//  Created by ant on 2017/10/25.
//  Copyright © 2017年 github.cornerant. All rights reserved.
//

import CommonCrypto
import Foundation

public enum DiggerCache {
    ///  In the sandbox cactes directory, custom your cache directory
    public static var cachesDirectory: String = digger {
        willSet {
            createDirectory(atPath: newValue.cacheDir)
        }
    }

    static func tempPath(url: URL) -> String {
        url.absoluteString.sha1().tmpDir
    }

    static func cachePath(url: URL) -> String {
        cachesDirectory.cacheDir + "/" + url.lastPathComponent
    }

    static func removeTempFile(with url: URL) {
        let fileTempParh = tempPath(url: url)
        if isFileExist(atPath: fileTempParh) {
            removeItem(atPath: fileTempParh)
        }
    }

    static func removeCacheFile(with url: URL) {
        let fileCachePath = cachePath(url: url)
        if isFileExist(atPath: fileCachePath) {
            removeItem(atPath: fileCachePath)
        }
    }

    /// The size of the downloaded files
    public static func downloadedFilesSize() -> Int64 {
        if !isFileExist(atPath: cachesDirectory.cacheDir) {
            return 0
        }
        do {
            var filesSize: Int64 = 0

            let subpaths = try FileManager.default.subpathsOfDirectory(atPath: cachesDirectory.cacheDir)

            _ = subpaths.map {
                let filepath = cachesDirectory.cacheDir + "/" + $0
                filesSize += fileSize(filePath: filepath)
            }
            return filesSize

        } catch {
            diggerLog(error)
            return 0
        }
    }

    /// delete all downloaded files
    public static func cleanDownloadTempFiles() {
        do {
            let subpaths = try FileManager.default.subpathsOfDirectory(atPath: "".tmpDir)
            _ = subpaths.map {
                let tempFilepath = "".tmpDir + "/" + $0

                removeItem(atPath: tempFilepath)
            }
        } catch {
            diggerLog(error)
        }
    }

    /// delete all  temp files
    public static func cleanDownloadFiles() {
        removeItem(atPath: cachesDirectory.cacheDir)
        createDirectory(atPath: cachesDirectory.cacheDir)
    }

    /// paths to the downloaded files
    public static func pathsOfDownloadedfiles() -> [String] {
        var paths = [String]()
        do {
            let subpaths = try FileManager.default.subpathsOfDirectory(atPath: cachesDirectory.cacheDir)

            _ = subpaths.map {
                let filepath = cachesDirectory.cacheDir + "/" + $0
                paths.append(filepath)
            }
        } catch {
            diggerLog(error)
        }

        return paths
    }
}

// MARK: - fileHelper

public extension DiggerCache {
    /// isFileExist
    static func isFileExist(atPath filePath: String) -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    /// fileSize
    static func fileSize(filePath: String) -> Int64 {
        guard isFileExist(atPath: filePath) else { return 0 }
        let fileInfo = try! FileManager.default.attributesOfItem(atPath: filePath)
        return fileInfo[FileAttributeKey.size] as! Int64
    }

    /// move file
    static func moveItem(atPath: String, toPath: String) {
        do {
            try FileManager.default.moveItem(atPath: atPath, toPath: toPath)
        } catch {
            diggerLog(error)
        }
    }

    /// delete file
    static func removeItem(atPath: String) {
        guard isFileExist(atPath: atPath) else {
            return
        }

        do {
            try FileManager.default.removeItem(atPath: atPath)
        } catch {
            diggerLog(error)
        }
    }

    /// createDirectory
    static func createDirectory(atPath: String) {
        if !isFileExist(atPath: atPath) {
            do {
                try FileManager.default.createDirectory(atPath: atPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                diggerLog(error)
            }
        }
    }

    /// systemFreeSize

    static func systemFreeSize() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let freesize = attributes[FileAttributeKey.systemFreeSize] as? Int64

            return freesize ?? 0

        } catch {
            diggerLog(error)
            return 0
        }
    }
}

// MARK: - SandboxPath

public extension String {
    var cacheDir: String {
        let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).last!
        return (path as NSString).appendingPathComponent((self as NSString).lastPathComponent)
    }

    var docDir: String {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last!
        return (path as NSString).appendingPathComponent((self as NSString).lastPathComponent)
    }

    var tmpDir: String {
        let path = NSTemporaryDirectory() as NSString
        return path.appendingPathComponent((self as NSString).lastPathComponent)
    }

    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
