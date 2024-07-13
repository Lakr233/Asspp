//
//  ApplePackage.swift
//  IPATool
//
//  Created by QAQ on 2023/10/4.
//

import Foundation

public enum ApplePackage {
    public static var overrideGUID: String?
    public static var countryCodeMap: [String: String] {
        storeFrontCodeMap // TWO LETTER = NUMBER
    }
}
