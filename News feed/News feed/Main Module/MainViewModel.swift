//
//  MainViewModel.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import Foundation
import Combine

protocol MainViewModelProtocol: AnyObject {
    var itemsPublisher: AnyPublisher<[NewsData], Never> { get }
    func loadPage(reset: Bool)
    func countOfNews() -> Int
    func newsItem(at index: Int) -> NewsData
}

final class MainViewModel: MainViewModelProtocol {
    private let repository: NewsRepositoryProtocol
    private let livenessService: LivenessServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var currentPage: Int = 0
    private let pageLimit: Int = 10
    @Published private var items: [NewsData] = []
    var itemsPublisher: AnyPublisher<[NewsData], Never> {
        $items.eraseToAnyPublisher()
    }

    init(repository: NewsRepositoryProtocol, livenessService: LivenessServiceProtocol) {
        self.repository = repository
        self.livenessService = livenessService
        bind()
    }
    private func bind() {
        repository.newsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] news in
                self?.items = news
            }
            .store(in: &cancellables)
    }
    func loadPage(reset: Bool) {
        if reset {
            currentPage = 1
        } else if currentPage == 0 {
            currentPage = 1
        }

        let pageToLoad = currentPage
        let limit = pageLimit

        Task {
            do {
                try await repository.fetchNewsThenImages(page: pageToLoad, limit: limit)
                let online = await livenessService.isOnline()
                
                await MainActor.run {
                    if online {
                        self.currentPage = pageToLoad + 1
                    }
                }
            } catch {
                print("Ошибка загрузки данных (page=\(pageToLoad), limit=\(limit)): \(error)")
            }
        }
    }
    func countOfNews() -> Int {
        items.count
    }
    func newsItem(at index: Int) -> NewsData {
        items[index]
    }
}
