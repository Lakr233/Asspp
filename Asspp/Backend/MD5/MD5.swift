//
//  MD5.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import CommonCrypto
import CryptoKit
import Foundation

func md5File(url: URL) -> String? {
    do {
        var hasher = Insecure.MD5()
        let bufferSize = 1024 * 1024 * 32 // 32MB

        let fileHandler = try FileHandle(forReadingFrom: url)
        fileHandler.seekToEndOfFile()
        let size = fileHandler.offsetInFile
        try fileHandler.seek(toOffset: 0)

        while fileHandler.offsetInFile < size {
            autoreleasepool {
                let data = fileHandler.readData(ofLength: bufferSize)
                hasher.update(data: data)
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    } catch {
        print("[-] error reading file: \(error)")
        return nil
    }
}
