//
//  NetworkReachability.swift
//  News feed
//
//  Created by Василий Максимов on 26.11.2025.
//

import Foundation
import Network

protocol LivenessServiceProtocol: AnyObject {
    func isOnline() async -> Bool
}

final class NetworkLivenessService: LivenessServiceProtocol {
    private let testURL: URL
    private let timeout: TimeInterval

    init(testURL: URL? = nil, timeout: TimeInterval = 1.5) {
        if let url = testURL {
            self.testURL = url
        } else {
            var components = URLComponents(string: "https://jsonplaceholder.typicode.com/posts")!
            components.queryItems = [URLQueryItem(name: "_limit", value: "1")]
            self.testURL = components.url!
        }
        self.timeout = timeout
    }

    func isOnline() async -> Bool {
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
