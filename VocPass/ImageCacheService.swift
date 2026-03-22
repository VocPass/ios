//
//  ImageCacheService.swift
//  VocPass
//

import UIKit

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCacheURL: URL

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("VocPassImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) async throws -> UIImage {
        let key = url as NSURL

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let filePath = diskFilePath(for: url)
        if let data = try? Data(contentsOf: filePath), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryCache.setObject(image, forKey: key, cost: data.count)
        try? data.write(to: filePath)

        return image
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        print("🗑️ [ImageCache] 已清除所有圖片快取")
    }

    func cacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            total += size
        }
        return total
    }

    private func diskFilePath(for url: URL) -> URL {
        let hash = abs(url.absoluteString.hashValue)
        return diskCacheURL.appendingPathComponent("\(hash)")
    }
}
