//
//  NetworkServiceWithAlamofire.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import Foundation
import Alamofire

protocol NetworkServiceProtocol: AnyObject {
    func fetchData<T: Decodable>(url: URL) async throws -> T
    func fetchImageData(url: URL) async throws -> Data
}

final class NetworkServiceWithAlamofire: NetworkServiceProtocol {
    func fetchData<T: Decodable>(url: URL) async throws -> T {
        try await AF.request(url)
            .validate()
            .serializingDecodable(T.self)
            .value
    }
    
    func fetchImageData(url: URL) async throws -> Data {
        try await AF.request(url)
            .validate()
            .serializingData()
            .value
    }
}
