//
//  NewsRepository.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//


import Foundation
import Combine
import CoreData

protocol NewsRepositoryProtocol {
    func fetchNewsThenImages(page: Int, limit: Int) async throws
    var newsPublisher: AnyPublisher<[NewsData], Never> { get }
}

final class NewsRepository: NewsRepositoryProtocol {
    private let networkService: NetworkServiceProtocol
    private let context: NSManagedObjectContext
    private let livenessService: LivenessServiceProtocol
    private var assembledCache: [NewsData] = [] {
        didSet { newsSubject.send(assembledCache) }
    }
    
    private let avatarState = AvatarState()
    private let newsSubject = CurrentValueSubject<[NewsData], Never>([])
    var newsPublisher: AnyPublisher<[NewsData], Never> { newsSubject.eraseToAnyPublisher() }

    init(
        networkService: NetworkServiceProtocol,
        context: NSManagedObjectContext,
        livenessService: LivenessServiceProtocol
    ) {
        self.networkService = networkService
        self.context = context
        self.livenessService = livenessService
    }
    
    // MARK: - Public API
    
    func fetchNewsThenImages(page: Int, limit: Int) async throws {
        let online = await livenessService.isOnline()
        var localAssembled = assembledCache
        guard online else {
            print("Интернета нет — читаем из Core Data (batch)")
            let cachedNews = await fetchNewsFromCoreData()
            let userIds = Set(cachedNews.map { $0.userId })
            let imagesFromCoreData = await fetchImagesFromCoreData(for: userIds)
            localAssembled = assembleNewsData(from: cachedNews, images: imagesFromCoreData)
            assembledCache = localAssembled
            return
        }
        do {
            if page == 1 {
                try await clearAllStoredData()
                localAssembled = []
            }
            
            let newNews = try await fetchNews(page: page, limit: limit)
            guard !newNews.isEmpty else {
                assembledCache = localAssembled
                return
            }
            var neededUserIds = Set(newNews.map { $0.userId })
            let existingImages = await fetchImagesFromCoreData(for: neededUserIds)
            for uid in existingImages.keys {
                neededUserIds.remove(uid)
            }
            let failed = await avatarState.failedUserIds()
            neededUserIds.formUnion(failed.intersection(neededUserIds))
            let inFlight = await avatarState.inFlightUserIds()
            neededUserIds.subtract(inFlight)
            
            if !neededUserIds.isEmpty {
                await withTaskGroup(of: Void.self) { group in
                    for userId in neededUserIds {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            await self.avatarState.markInFlight(userId)
                            defer { Task { await self.avatarState.unmarkInFlight(userId) } }
                            
                            do {
                                let data = try await self.fetchAvatarDataOnly(userId: userId)
                                try? await self.upsertImage(userId: userId, data: data)
                                await self.avatarState.removeFailed(userId)
                            } catch {
                                await self.avatarState.addFailed(userId)
                            }
                        }
                    }
                }
            }
            
            let finalImages = await fetchImagesFromCoreData(for: Set(newNews.map { $0.userId }))
            let pageData = assembleNewsData(from: newNews, images: finalImages)
            if page == 1 {
                localAssembled = pageData
            } else {
                localAssembled.append(contentsOf: pageData)
            }
            
            assembledCache = localAssembled
        } catch {
            print("Ошибка сети — офлайн batch. Ошибка: \(error)")
            let cachedNews = await fetchNewsFromCoreData()
            let userIds = Set(cachedNews.map { $0.userId })
            let imagesFromCD = await fetchImagesFromCoreData(for: userIds)
            localAssembled = assembleNewsData(from: cachedNews, images: imagesFromCD)
            assembledCache = localAssembled
        }
    }
    
    // MARK: - Network helpers
    
    private func fetchNews(page: Int, limit: Int) async throws -> [News] {
        guard let url = createNewsURL(page: page, limit: limit) else {
            throw URLError(.badURL)
        }
        let news: [News] = try await networkService.fetchData(url: url)
        guard !news.isEmpty else { return [] }
        try await saveNewsToCoreData(news)
        return news
    }
    
    private func fetchAvatarDataOnly(userId: Int) async throws -> Data {
        guard let url = URL(string: "https://picsum.photos/seed/\(userId)/80/80") else {
            throw URLError(.badURL)
        }
        return try await networkService.fetchImageData(url: url)
    }
    
    private func createNewsURL(page: Int, limit: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "jsonplaceholder.typicode.com"
        components.path = "/posts"
        components.queryItems = [
            URLQueryItem(name: "_page", value: String(page)),
            URLQueryItem(name: "_limit", value: String(limit))
        ]
        return components.url
    }
}

// MARK: - Core Data saving/loading
private extension NewsRepository {

    func clearAllStoredData() async throws {
        try await context.perform {
            do {
                let fetchNews: NSFetchRequest<NSFetchRequestResult> = NewsFeed.fetchRequest()
                let deleteNews = NSBatchDeleteRequest(fetchRequest: fetchNews)
                try self.context.execute(deleteNews)
            }
            do {
                let fetchImages: NSFetchRequest<NSFetchRequestResult> = ImageEntity.fetchRequest()
                let deleteImages = NSBatchDeleteRequest(fetchRequest: fetchImages)
                try self.context.execute(deleteImages)
            }
            
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
    
    func saveNewsToCoreData(_ items: [News]) async throws {
        try await context.perform {
            for item in items {
                let fetch: NSFetchRequest<NewsFeed> = NewsFeed.fetchRequest()
                fetch.fetchLimit = 1
                fetch.predicate = NSPredicate(format: "postId == %d", Int64(item.id))
                
                let entity: NewsFeed
                if let existing = try self.context.fetch(fetch).first {
                    entity = existing
                } else {
                    entity = NewsFeed(context: self.context)
                    if entity.value(forKey: "id") == nil {
                        entity.setValue(UUID(), forKey: "id")
                    }
                    entity.postId = Int64(item.id)
                }
                
                entity.userId = Int64(item.userId)
                entity.title = item.title
                entity.body = item.body
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
    
    func upsertImage(userId: Int, data: Data) async throws {
        try await context.perform {
            let fetch: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetch.fetchLimit = 1
            fetch.predicate = NSPredicate(format: "userId == %d", Int64(userId))
            
            let entity: ImageEntity
            if let existing = try self.context.fetch(fetch).first {
                entity = existing
            } else {
                entity = ImageEntity(context: self.context)
                entity.userId = Int64(userId)
            }
            entity.imageData = data
            
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
    
    func fetchNewsFromCoreData() async -> [News] {
        await context.perform {
            let request: NSFetchRequest<NewsFeed> = NewsFeed.fetchRequest()
            let sort = NSSortDescriptor(key: "postId", ascending: true)
            request.sortDescriptors = [sort]
            do {
                let objects = try self.context.fetch(request)
                return objects.map { obj in
                    News(
                        userId: Int(obj.userId),
                        id: Int(obj.postId),
                        title: obj.title ?? "",
                        body: obj.body ?? ""
                    )
                }
            } catch {
                return []
            }
        }
    }
    
    func fetchImagesFromCoreData(for userIds: Set<Int>) async -> [Int: Data] {
        guard !userIds.isEmpty else { return [:] }
        return await context.perform {
            let request: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            let ids64 = userIds.map { Int64($0) }
            request.predicate = NSPredicate(format: "userId IN %@", ids64 as NSArray)
            do {
                let images = try self.context.fetch(request)
                var dict: [Int: Data] = [:]
                for img in images {
                    let uid = Int(img.userId)
                    if let data = img.imageData {
                        dict[uid] = data
                    }
                }
                return dict
            } catch {
                return [:]
            }
        }
    }
    
    func assembleNewsData(from news: [News], images: [Int: Data]) -> [NewsData] {
        news.map { item in
            NewsData(
                userId: item.userId,
                title: item.title,
                body: item.body,
                data: images[item.userId]
            )
        }
    }
}

// MARK: - Concurrency-safe avatar state
private actor AvatarState {
    private var inFlight = Set<Int>()
    private var failed  = Set<Int>()
    
    func inFlightUserIds() -> Set<Int> { inFlight }
    func failedUserIds() -> Set<Int> { failed }
    
    func markInFlight(_ userId: Int) {
        inFlight.insert(userId)
    }
    func unmarkInFlight(_ userId: Int) {
        inFlight.remove(userId)
    }
    func addFailed(_ userId: Int) {
        failed.insert(userId)
    }
    func removeFailed(_ userId: Int) {
        failed.remove(userId)
    }
}
