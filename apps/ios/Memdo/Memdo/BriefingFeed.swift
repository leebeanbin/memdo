import Foundation
import FoundationModels

// MARK: - Category Catalog

enum BriefingFeedCategory: String, CaseIterable, Identifiable {
    case economy = "경제"
    case tech    = "IT/테크"
    case startup = "스타트업"
    case world   = "글로벌"
    case general = "종합"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .economy:  "chart.line.uptrend.xyaxis"
        case .tech:     "cpu"
        case .startup:  "bolt.horizontal"
        case .world:    "globe.asia.australia"
        case .general:  "newspaper"
        }
    }

    // All RSS URLs verified reachable as of 2026-08. Update here when feeds move.
    var feeds: [BriefingFeedSource] {
        switch self {
        case .economy: [
            BriefingFeedSource(id: "mk", name: "매일경제", url: "https://www.mk.co.kr/rss/30000001/", category: self),
        ]
        case .tech: [
            BriefingFeedSource(id: "techcrunch", name: "TechCrunch", url: "https://techcrunch.com/feed/", category: self),
            BriefingFeedSource(id: "verge",      name: "The Verge",   url: "https://www.theverge.com/rss/index.xml", category: self),
        ]
        case .startup: [
            BriefingFeedSource(id: "platum",     name: "플래텀",      url: "https://platum.kr/feed", category: self),
            BriefingFeedSource(id: "tc-startup", name: "TechCrunch",  url: "https://techcrunch.com/category/startups/feed/", category: self),
        ]
        case .world: [
            BriefingFeedSource(id: "hn",    name: "Hacker News", url: "https://news.ycombinator.com/rss", category: self),
            BriefingFeedSource(id: "verge2",name: "The Verge",   url: "https://www.theverge.com/rss/index.xml", category: self),
        ]
        case .general: [
            BriefingFeedSource(id: "yonhap", name: "연합뉴스", url: "https://www.yna.co.kr/rss/news.xml", category: self),
            BriefingFeedSource(id: "mk-gen", name: "매일경제", url: "https://www.mk.co.kr/rss/30000001/", category: self),
        ]
        }
    }
}

struct BriefingFeedSource: Identifiable {
    let id: String
    let name: String
    let urlString: String
    let category: BriefingFeedCategory

    init(id: String, name: String, url urlString: String, category: BriefingFeedCategory) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.category = category
    }

    var rssURL: URL? { URL(string: urlString) }
}

// MARK: - RSS XML Parser

private final class RSSParser: NSObject, XMLParserDelegate {
    struct RSSItem {
        var title       = ""
        var link        = ""
        var description = ""
        var pubDate     = ""
    }

    private(set) var items: [RSSItem] = []
    private var insideItem  = false
    private var currentItem = RSSItem()
    private var currentText = ""

    func parse(data: Data) -> [RSSItem] {
        items.removeAll()
        insideItem  = false
        currentItem = RSSItem()
        currentText = ""
        let parser  = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == "item" || elementName == "entry" {
            insideItem  = true
            currentItem = RSSItem()
        }
        // Atom feeds carry the URL in <link href="..."/> (self-closing, no text
        // content); rel is absent or "alternate" for the article link.
        if insideItem, elementName == "link", currentItem.link.isEmpty,
           let href = attributeDict["href"],
           attributeDict["rel"] == nil || attributeDict["rel"] == "alternate" {
            currentItem.link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { currentText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if insideItem, let s = String(data: CDATABlock, encoding: .utf8) { currentText += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard insideItem else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title"       where currentItem.title.isEmpty:       currentItem.title = text
        case "link"        where currentItem.link.isEmpty:        currentItem.link = text
        case "description", "summary":
            if currentItem.description.isEmpty { currentItem.description = text.strippingHTMLTags }
        case "pubDate", "published", "updated":
            if currentItem.pubDate.isEmpty { currentItem.pubDate = text }
        case "item", "entry":
            if !currentItem.title.isEmpty { items.append(currentItem) }
            insideItem = false
        default: break
        }
        currentText = ""
    }
}

private extension String {
    var strippingHTMLTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Repository

actor BriefingRepository {
    struct FetchedItem: Identifiable, Sendable {
        let id: String
        let title: String
        let summary: String
        let url: URL?
        let sourceName: String
        let category: BriefingFeedCategory
        let publishedAt: Date?
        let matchedKeyword: String?

        var relativeTime: String {
            guard let date = publishedAt else { return "" }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            f.locale = Locale(identifier: "ko_KR")
            return f.localizedString(for: date, relativeTo: .now)
        }
    }

    static let shared = BriefingRepository()

    /// Fetch articles for the given categories, optionally filtered by keywords.
    /// Returns at most 20 items sorted newest-first, deduplicated by URL.
    func fetch(categories: [BriefingFeedCategory], keywords: [String]) async -> [FetchedItem] {
        let feeds = categories.flatMap { $0.feeds }
        guard !feeds.isEmpty else { return [] }

        var result: [FetchedItem] = []
        await withTaskGroup(of: [FetchedItem].self) { group in
            for feed in feeds {
                group.addTask { await self.fetchFeed(feed, keywords: keywords) }
            }
            for await items in group { result += items }
        }

        var seen = Set<String>()
        let deduped = result.filter { item in
            let key = item.url?.absoluteString ?? item.title
            return seen.insert(key).inserted
        }
        return Array(
            deduped
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                .prefix(20)
        )
    }

    private func fetchFeed(_ feed: BriefingFeedSource, keywords: [String]) async -> [FetchedItem] {
        guard let rssURL = feed.rssURL,
              let (data, _) = try? await URLSession.shared.data(from: rssURL) else { return [] }

        let parser = RSSParser()
        let rssItems = parser.parse(data: data)

        return rssItems.compactMap { item in
            guard !item.title.isEmpty else { return nil }
            let searchText = (item.title + " " + item.description).lowercased()
            let matched: String?
            if keywords.isEmpty {
                matched = nil
            } else {
                matched = keywords.first { searchText.contains($0.lowercased()) }
                guard matched != nil else { return nil }
            }
            return FetchedItem(
                id: item.link.isEmpty ? item.title : item.link,
                title: item.title,
                summary: String(item.description.prefix(200)),
                url: URL(string: item.link),
                sourceName: feed.name,
                category: feed.category,
                publishedAt: parseDate(item.pubDate),
                matchedKeyword: matched
            )
        }
    }

    private func parseDate(_ string: String) -> Date? {
        // RFC 2822: "Wed, 13 Aug 2026 08:30:00 +0900"
        let rfc2822 = DateFormatter()
        rfc2822.locale = Locale(identifier: "en_US_POSIX")
        rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = rfc2822.date(from: string) { return d }

        // ISO 8601 with/without fractional seconds
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }

    // MARK: - Cache

    private static let cacheDefaultsKey = "briefing-repo-cache"

    /// Returns cached items for today if categories/keywords match; otherwise fetches fresh.
    func fetchWithCache(categories: [BriefingFeedCategory], keywords: [String]) async -> [FetchedItem] {
        let today  = currentDateString()
        let catKey = categories.map(\.rawValue).sorted().joined(separator: ",")
        let kwKey  = keywords.sorted().joined(separator: ",")

        if let data  = UserDefaults.standard.data(forKey: Self.cacheDefaultsKey),
           let cache = try? JSONDecoder().decode(BriefingCache.self, from: data),
           cache.date == today, cache.catKey == catKey, cache.kwKey == kwKey {
            return cache.items.compactMap { $0.toFetchedItem() }
        }

        let items = await fetch(categories: categories, keywords: keywords)
        let entry = BriefingCache(date: today, catKey: catKey, kwKey: kwKey,
                                  items: items.map(BriefingCache.Item.init))
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: Self.cacheDefaultsKey)
        }
        return items
    }

    private func currentDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    // MARK: - On-device AI Summary

    private static let summaryCacheKey = "briefing-summary-cache-v5"

    /// Generates a Korean trend summary from the top articles using the on-device model.
    /// Returns a cached result for the same day + same category/keyword combination.
    @available(iOS 26, *)
    func summarize(items: [FetchedItem],
                   categories: [BriefingFeedCategory],
                   keywords: [String]) async -> String? {
        guard !items.isEmpty else { return nil }

        let today  = currentDateString()
        let catKey = categories.map(\.rawValue).sorted().joined(separator: ",")
        let kwKey  = keywords.sorted().joined(separator: ",")

        // Return cached summary when same day + same interests
        if let data  = UserDefaults.standard.data(forKey: Self.summaryCacheKey),
           let cache = try? JSONDecoder().decode(SummaryCache.self, from: data),
           cache.date == today, cache.catKey == catKey, cache.kwKey == kwKey {
            return cache.summary
        }

        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let headlines = items.prefix(5).enumerated().map { i, item in
            "\(i + 1). [\(item.category.rawValue)] \(item.title)"
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: "관심 분야 뉴스에서 연결되는 구체적인 변화 하나를 한국어 편집 헤드라인으로 써. 숫자·기업명·기술명 중 하나를 반드시 포함하고, 독자가 다음 내용을 궁금해하게 만들어. 과장과 낚시는 금지해. 22~36자, 최대 두 줄, 마침표 없이 제목만 출력해. '미치는 영향', '전망', '동향', '주목', '가속화', '혁신' 같은 추상 표현은 쓰지 마."
        )
        let prompt = "오늘의 주요 뉴스:\n\(headlines)\n\n기사 사이의 연결이 보이는 구체적인 제목 하나를 써줘."

        guard let response = try? await session.respond(to: prompt) else { return nil }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let entry = SummaryCache(date: today, catKey: catKey, kwKey: kwKey, summary: text)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: Self.summaryCacheKey)
        }
        return text
    }
}

// MARK: - Persistent Cache Structures (file-private)

private struct SummaryCache: Codable {
    let date: String
    let catKey: String
    let kwKey: String
    let summary: String
}

// MARK: - Cache Storage (file-private, not persisted beyond one day)

private struct BriefingCache: Codable {
    let date: String
    let catKey: String
    let kwKey: String
    let items: [Item]

    struct Item: Codable {
        let id: String
        let title: String
        let summary: String
        let urlString: String?
        let sourceName: String
        let categoryRaw: String
        let publishedAtInterval: TimeInterval?
        let matchedKeyword: String?

        init(from item: BriefingRepository.FetchedItem) {
            id                   = item.id
            title                = item.title
            summary              = item.summary
            urlString            = item.url?.absoluteString
            sourceName           = item.sourceName
            categoryRaw          = item.category.rawValue
            publishedAtInterval  = item.publishedAt?.timeIntervalSince1970
            matchedKeyword       = item.matchedKeyword
        }

        func toFetchedItem() -> BriefingRepository.FetchedItem? {
            guard let category = BriefingFeedCategory(rawValue: categoryRaw) else { return nil }
            return BriefingRepository.FetchedItem(
                id: id, title: title, summary: summary,
                url: urlString.flatMap(URL.init),
                sourceName: sourceName, category: category,
                publishedAt: publishedAtInterval.map(Date.init(timeIntervalSince1970:)),
                matchedKeyword: matchedKeyword
            )
        }
    }
}
