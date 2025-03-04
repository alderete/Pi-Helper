//
//  PiHoleApiService.swift
//  Pi-Helper
//
//  Created by Billy Brawner on 10/19/19.
//  Copyright © 2019 William Brawner. All rights reserved.
//

import Foundation
import Combine

class PiHoleApiService {
    let decoder: JSONDecoder
    var baseUrl: String? = nil
    var apiKey: String? = nil
    
    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    func getVersion() -> AnyPublisher<VersionResponse, NetworkError> {
        return get(queries: ["version": nil])
    }
    
    func loadSummary() -> AnyPublisher<PiHole, NetworkError> {
        return get()
    }
    
    func enable() -> AnyPublisher<StatusUpdate, NetworkError> {
        return get(true, queries: ["enable": nil])
    }
    
    func disable(_ forSeconds: Int? = nil) -> AnyPublisher<StatusUpdate, NetworkError> {
        var params = [String: String?]()
        if let timeToDisable = forSeconds {
            params["disable"] = String(timeToDisable)
        } else {
            params["disable"] = nil
        }
        return get(true, queries: params)
    }

    private func get<ResultType: Codable>(
        _ requiresAuth: Bool = false,
        queries: [String: String?]? = nil
    ) -> AnyPublisher<ResultType, NetworkError> {
        guard let baseUrl = self.baseUrl else {
            return Result<ResultType, NetworkError>.Publisher(.failure(.invalidUrl))
                .eraseToAnyPublisher()
        }
        
        var combinedEndPoint = baseUrl + "/admin/api.php"
        
        var modifiedQueries = queries ?? [:]
        if requiresAuth, let apiKey = self.apiKey {
            modifiedQueries["auth"] = apiKey
        }
        for (key, value) in modifiedQueries {
            let separator = combinedEndPoint.contains("?") ? "&" : "?"
            combinedEndPoint += separator + key
            if let notNilValue = value {
                combinedEndPoint += "=" + notNilValue
            }
        }
        
        guard let url = URL(string: combinedEndPoint) else {
            return Result.Publisher(.failure(.invalidUrl)).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "GET"
        request.timeoutInterval = 0.5
        
        let task = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { (data, res) -> Data in
                guard let response = res as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                    switch (res as? HTTPURLResponse)?.statusCode {
                    case 400: throw NetworkError.badRequest
                    case 401, 403: throw NetworkError.unauthorized
                    case 404: throw NetworkError.notFound
                    default: throw NetworkError.unknown
                    }
                }
                return data
        }
        .decode(type: ResultType.self, decoder: self.decoder)
        .mapError {
            return NetworkError.jsonParsingFailed($0)
        }
        return task.eraseToAnyPublisher()
    }
}

enum NetworkError: Error {
    case loading
    case cancelled
    case badRequest
    case notFound
    case unauthorized
    case unknown
    case invalidUrl
    case jsonParsingFailed(Error)
}

struct Empty: Codable {}
