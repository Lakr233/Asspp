//
//  StoreClient.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

let storeFrontCodeMap = [
    "AE": "143481",
    "AG": "143540",
    "AI": "143538",
    "AL": "143575",
    "AM": "143524",
    "AO": "143564",
    "AR": "143505",
    "AT": "143445",
    "AU": "143460",
    "AZ": "143568",
    "BB": "143541",
    "BD": "143490",
    "BE": "143446",
    "BG": "143526",
    "BH": "143559",
    "BM": "143542",
    "BN": "143560",
    "BO": "143556",
    "BR": "143503",
    "BS": "143539",
    "BW": "143525",
    "BY": "143565",
    "BZ": "143555",
    "CA": "143455",
    "CH": "143459",
    "CI": "143527",
    "CL": "143483",
    "CN": "143465",
    "CO": "143501",
    "CR": "143495",
    "CY": "143557",
    "CZ": "143489",
    "DE": "143443",
    "DK": "143458",
    "DM": "143545",
    "DO": "143508",
    "DZ": "143563",
    "EC": "143509",
    "EE": "143518",
    "EG": "143516",
    "ES": "143454",
    "FI": "143447",
    "FR": "143442",
    "GB": "143444",
    "GD": "143546",
    "GE": "143615",
    "GH": "143573",
    "GR": "143448",
    "GT": "143504",
    "GY": "143553",
    "HK": "143463",
    "HN": "143510",
    "HR": "143494",
    "HU": "143482",
    "ID": "143476",
    "IE": "143449",
    "IL": "143491",
    "IN": "143467",
    "IS": "143558",
    "IT": "143450",
    "JM": "143511",
    "JO": "143528",
    "JP": "143462",
    "KE": "143529",
    "KN": "143548",
    "KR": "143466",
    "KW": "143493",
    "KY": "143544",
    "KZ": "143517",
    "LB": "143497",
    "LC": "143549",
    "LI": "143522",
    "LK": "143486",
    "LT": "143520",
    "LU": "143451",
    "LV": "143519",
    "MD": "143523",
    "MG": "143531",
    "MK": "143530",
    "ML": "143532",
    "MN": "143592",
    "MO": "143515",
    "MS": "143547",
    "MT": "143521",
    "MU": "143533",
    "MV": "143488",
    "MX": "143468",
    "MY": "143473",
    "NE": "143534",
    "NG": "143561",
    "NI": "143512",
    "NL": "143452",
    "NO": "143457",
    "NP": "143484",
    "NZ": "143461",
    "OM": "143562",
    "PA": "143485",
    "PE": "143507",
    "PH": "143474",
    "PK": "143477",
    "PL": "143478",
    "PT": "143453",
    "PY": "143513",
    "QA": "143498",
    "RO": "143487",
    "RS": "143500",
    "RU": "143469",
    "SA": "143479",
    "SE": "143456",
    "SG": "143464",
    "SI": "143499",
    "SK": "143496",
    "SN": "143535",
    "SR": "143554",
    "SV": "143506",
    "TC": "143552",
    "TH": "143475",
    "TN": "143536",
    "TR": "143480",
    "TT": "143551",
    "TW": "143470",
    "TZ": "143572",
    "UA": "143492",
    "UG": "143537",
    "US": "143441",
    "UY": "143514",
    "UZ": "143566",
    "VC": "143550",
    "VE": "143502",
    "VG": "143543",
    "VN": "143471",
    "YE": "143571",
    "ZA": "143472",
]

public protocol StoreClientInterface {
    func authenticate(email: String, password: String, code: String?, completion: @escaping (Result<StoreResponse.Account, Error>) -> Void)
    func item(identifier: String, directoryServicesIdentifier: String, completion: @escaping (Result<StoreResponse.Item, Error>) -> Void)
    func buy(token: String, directoryServicesIdentifier: String, trackID: Int, countryCode: String, completion: @escaping (Result<Void, Error>) -> Void)
}

public extension StoreClientInterface {
    func authenticate(email: String,
                      password: String,
                      code: String? = nil,
                      completion: @escaping (Result<StoreResponse.Account, Swift.Error>) -> Void)
    {
        authenticate(email: email, password: password, code: code, completion: completion)
    }

    func authenticate(email: String, password: String, code: String? = nil) throws -> StoreResponse.Account {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<StoreResponse.Account, Error>?

        authenticate(email: email, password: password, code: code) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        switch result {
        case .none:
            throw StoreClient.Error.timeout
        case let .failure(error):
            throw error
        case let .success(result):
            return result
        }
    }

    func item(identifier: String, directoryServicesIdentifier: String) throws -> StoreResponse.Item {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<StoreResponse.Item, Error>?

        item(identifier: identifier, directoryServicesIdentifier: directoryServicesIdentifier) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        switch result {
        case .none:
            throw StoreClient.Error.timeout
        case let .failure(error):
            throw error
        case let .success(result):
            return result
        }
    }

    func buy(token: String, directoryServicesIdentifier: String, trackID: Int, countryCode: String) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error>?

        buy(token: token, directoryServicesIdentifier: directoryServicesIdentifier, trackID: trackID, countryCode: countryCode) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        switch result {
        case .none:
            throw StoreClient.Error.timeout
        case let .failure(error):
            throw error
        case let .success(result):
            return result
        }
    }
}

public final class StoreClient: StoreClientInterface {
    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    public func authenticate(email: String, password: String, code: String?, completion: @escaping (Result<StoreResponse.Account, Swift.Error>) -> Void) {
        authenticate(email: email,
                     password: password,
                     code: code,
                     isFirstAttempt: true,
                     completion: completion)
    }

    private func authenticate(email: String,
                              password: String,
                              code: String?,
                              isFirstAttempt: Bool,
                              completion: @escaping (Result<StoreResponse.Account, Swift.Error>) -> Void)
    {
        let request = StoreRequest.authenticate(email: email, password: password, code: code)

        httpClient.send(request) { [weak self] result in
            switch result {
            case let .success(response):
                do {
                    let decoded = try response.decode(StoreResponse.self, as: .xml)
                    var countryCode = ""
                    if let storeFront = response.allHeaderFields["x-set-apple-store-front"] as? String,
                       let storeFrontCode = storeFront.components(separatedBy: "-").first
                    {
                        for (key, value) in storeFrontCodeMap where value == storeFrontCode {
                            countryCode = key
                            break
                        }
                    }
                    switch decoded {
                    case let .account(account):
                        var account = account
                        account.countryCode = countryCode
                        completion(.success(account))
                    case .item:
                        completion(.failure(Error.invalidResponse))
                    case let .failure(error):
                        switch error {
                        case StoreResponse.Error.invalidCredentials:
                            if isFirstAttempt {
                                return self?.authenticate(email: email,
                                                          password: password,
                                                          code: code,
                                                          isFirstAttempt: false,
                                                          completion: completion) ?? ()
                            }

                            completion(.failure(error))
                        default:
                            completion(.failure(error))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func item(identifier: String, directoryServicesIdentifier: String, completion: @escaping (Result<StoreResponse.Item, Swift.Error>) -> Void) {
        let request = StoreRequest.download(appIdentifier: identifier, directoryServicesIdentifier: directoryServicesIdentifier)

        httpClient.send(request) { result in
            switch result {
            case let .success(response):
                do {
                    let decoded = try response.decode(StoreResponse.self, as: .xml)

                    switch decoded {
                    case let .item(item):
                        completion(.success(item))
                    case .account:
                        completion(.failure(Error.invalidResponse))
                    case let .failure(error):
                        completion(.failure(error))
                    }
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func buy(token: String, directoryServicesIdentifier: String, trackID: Int, countryCode: String, completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        // STDQ for generic request and GAME for arcade, but we support STDQ for now
        let request = StoreRequest.buy(token: token, directoryServicesIdentifier: directoryServicesIdentifier, trackID: trackID, countryCode: countryCode, pricingParameters: "STDQ")

        httpClient.send(request) { result in
            switch result {
            case let .success(response):
                do {
                    let code = response.statusCode
                    if code == 200,
                       let data = response.data,
                       let content = String(data: data, encoding: .utf8),
                       content.contains("purchaseSuccess")
                    {
                        // TODO: DO DECODE
                        completion(.success(()))
                    } else {
                        throw Error.unknownResponse
                    }
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

extension StoreClient {
    enum Error: Swift.Error {
        case timeout
        case invalidResponse
        case unknownResponse
    }
}

/*
 <?xml version="1.0" encoding="UTF-8" standalone="no"?>
 <plist version="1.0">
 <dict>
 <key>pings</key>
 <array></array>
 <key>jingleDocType</key><string>purchaseSuccess</string>
 <key>jingleAction</key><string>purchaseProduct</string>
 <key>status</key><integer>0</integer>
 */
