//
//  MainModel.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import Foundation

struct News: Decodable {
    let userId: Int
    let id: Int
    let title: String
    let body: String
}

struct NewsData {
    let userId: Int
    let title: String
    let body: String
    let data: Data?
}

