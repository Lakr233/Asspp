//
//  iTunesClient.swift
//  IPATool
//
//  Created by Majd Alfhaily on 22.05.21.
//

import Foundation

public protocol iTunesClientInterface {
    func lookup(type: EntityType, bundleIdentifier: String, region: String, completion: @escaping (Result<iTunesResponse.iTunesArchive, Error>) -> Void)
    func search(type: EntityType, term: String, limit: Int, region: String, completion: @escaping (Result<[iTunesResponse.iTunesArchive], Error>) -> Void)
}

public extension iTunesClientInterface {
    func lookup(type: EntityType, bundleIdentifier: String, region: String) throws -> iTunesResponse.iTunesArchive {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<iTunesResponse.iTunesArchive, Error>?

        lookup(type: type, bundleIdentifier: bundleIdentifier, region: region) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        switch result {
        case .none:
            throw iTunesClient.Error.timeout
        case let .failure(error):
            throw error
        case let .success(result):
            return result
        }
    }

    func search(type: EntityType, term: String, limit: Int, region: String) throws -> [iTunesResponse.iTunesArchive] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[iTunesResponse.iTunesArchive], Error>?

        search(type: type, term: term, limit: limit, region: region) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        switch result {
        case .none:
            throw iTunesClient.Error.timeout
        case let .failure(error):
            throw error
        case let .success(result):
            return result
        }
    }
}

public final class iTunesClient: iTunesClientInterface {
    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    public func lookup(type: EntityType, bundleIdentifier: String, region: String, completion: @escaping (Result<iTunesResponse.iTunesArchive, Swift.Error>) -> Void) {
        let request = iTunesRequest.lookup(type: type, bundleIdentifier: bundleIdentifier, region: region)

        httpClient.send(request) { result in
            switch result {
            case let .success(response):
                do {
                    let decoded = try response.decode(iTunesResponse.self, as: .json)
                    guard var result = decoded.results.first else { return completion(.failure(Error.appNotFound)) }
                    result.entityType = type
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func search(type: EntityType, term: String, limit: Int, region: String, completion: @escaping (Result<[iTunesResponse.iTunesArchive], Swift.Error>) -> Void) {
        let request = iTunesRequest.search(type: type, term: term, limit: limit, region: region)

        httpClient.send(request) { result in
            switch result {
            case let .success(response):
                do {
                    let decoded = try response.decode(iTunesResponse.self, as: .json)
                    completion(.success(decoded.results.map {
                        var archive = $0
                        archive.entityType = type
                        return archive
                    }))
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

extension iTunesClient {
    enum Error: Swift.Error {
        case timeout
        case appNotFound
    }
}
