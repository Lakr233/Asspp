//
//  iTunesEndpoint.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

enum iTunesEndpoint {
    case search
    case lookup
}

extension iTunesEndpoint: HTTPEndpoint {
    var url: URL {
        var components = URLComponents(string: path)!
        components.scheme = "https"
        components.host = "itunes.apple.com"
        return components.url!
    }

    private var path: String {
        switch self {
        case .search:
            "/search"
        case .lookup:
            "/lookup"
        }
    }
}

//
// func (t *appstore) purchaseRequest(acc Account, app App, storeFront, guid string, pricingParameters string) http.Request {
//    return http.Request{
//        URL:            fmt.Sprintf("https://%s%s", PrivateAppStoreAPIDomain, PrivateAppStoreAPIPathPurchase),
//        Method:         http.MethodPOST,
//        ResponseFormat: http.ResponseFormatXML,
//        Headers: map[string]string{
//            "Content-Type":        "application/x-apple-plist",
//            "iCloud-DSID":         acc.DirectoryServicesID,
//            "X-Dsid":              acc.DirectoryServicesID,
//            "X-Apple-Store-Front": storeFront,
//            "X-Token":             acc.PasswordToken,
//        },
//        Payload: &http.XMLPayload{
//            Content: map[string]interface{}{
//                "appExtVrsId":               "0",
//                "hasAskedToFulfillPreorder": "true",
//                "buyWithoutAuthorization":   "true",
//                "hasDoneAgeCheck":           "true",
//                "guid":                      guid,
//                "needDiv":                   "0",
//                "origPage":                  fmt.Sprintf("Software-%d", app.ID),
//                "origPageLocation":          "Buy",
//                "price":                     "0",
//                "pricingParameters":         pricingParameters,
//                "productType":               "C",
//                "salableAdamId":             app.ID,
//            },
//        },
//    }
// }
