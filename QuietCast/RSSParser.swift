import Foundation
import os

final class RSSParser: NSObject, XMLParserDelegate {
    private var episodes: [Episode] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentAudioURL = ""
    private var currentGUID = ""
    private var insideItem = false

    private var podcastTitle = ""
    private var podcastArtworkURL = ""
    private var feedURL: String
    private let logger = Logger(subsystem: "com.quietcast", category: "RSSParser")

    private static let rfc2822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// True when the last `parse(data:)` hit an XML error.
    private(set) var parseFailed = false

    init(feedURL: String) {
        self.feedURL = feedURL
    }

    func parse(data: Data) -> [Episode] {
        episodes = []
        parseFailed = false
        podcastTitle = ""
        podcastArtworkURL = ""
        // Convert to string, trying UTF-8 first, then Latin-1 as fallback
        let rawString: String
        if let str = String(data: data, encoding: .utf8) {
            rawString = str
        } else if let str = String(data: data, encoding: .isoLatin1) {
            rawString = str
        } else {
            rawString = String(decoding: data, as: UTF8.self)
        }

        // Strip invalid XML characters (control chars that XMLParser cannot handle).
        // Valid XML 1.0 chars: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
        let cleaned = rawString.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v == 0x9 || v == 0xA || v == 0xD ||
                   (v >= 0x20 && v <= 0xD7FF) ||
                   (v >= 0xE000 && v <= 0xFFFD) ||
                   (v >= 0x10000 && v <= 0x10FFFF)
        }
        let cleanedString = String(String.UnicodeScalarView(cleaned))

        // Fix common encoding declaration mismatches — force UTF-8 declaration
        // since we've already converted everything to UTF-8
        let finalString = cleanedString.replacingOccurrences(
            of: #"encoding\s*=\s*"[^"]*""#,
            with: #"encoding="UTF-8""#,
            options: .regularExpression
        )

        let cleanedData = Data(finalString.utf8)

        let parser = XMLParser(data: cleanedData)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        if !parser.parse() {
            parseFailed = true
        }
        return episodes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentDuration = ""
            currentAudioURL = ""
            currentGUID = ""
        }

        if elementName == "enclosure", insideItem {
            if let url = attributeDict["url"] {
                currentAudioURL = url
            }
        }

        if elementName == "itunes:image" || elementName == "image" {
            if !insideItem, let href = attributeDict["href"] {
                podcastArtworkURL = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title":
            if insideItem {
                currentTitle += string
            } else if podcastTitle.isEmpty {
                podcastTitle += string
            }
        case "description", "itunes:summary", "content:encoded":
            if insideItem {
                currentDescription += string
            }
        case "pubDate":
            if insideItem {
                currentPubDate += string
            }
        case "itunes:duration":
            if insideItem {
                currentDuration += string
            }
        case "guid":
            if insideItem {
                currentGUID += string
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false

            let guid = currentGUID.trimmingCharacters(in: .whitespacesAndNewlines)
            let audioURL = currentAudioURL.trimmingCharacters(in: .whitespacesAndNewlines)

            let rawPubDate = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)
            let (displayDate, timestamp) = parsePubDate(rawPubDate)

            let episode = Episode(
                guid: guid.isEmpty ? audioURL : guid,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                descriptionText: HTMLCleaner.clean(currentDescription),
                pubDate: displayDate,
                pubDateTimestamp: timestamp,
                duration: currentDuration.trimmingCharacters(in: .whitespacesAndNewlines),
                audioURL: audioURL,
                podcastTitle: podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                artworkURL: podcastArtworkURL
            )

            if !episode.audioURL.isEmpty {
                episodes.append(episode)
            }
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Don't clear episodes — return whatever we parsed before the error
        parseFailed = true
        logger.warning("RSS parse error for \(self.feedURL): \(parseError.localizedDescription)")
    }

    /// Parse an RFC 2822 pubDate into a display string and a timestamp.
    private func parsePubDate(_ raw: String) -> (display: String, timestamp: Double?) {
        if let date = Self.rfc2822Formatter.date(from: raw) {
            return (Self.displayDateFormatter.string(from: date), date.timeIntervalSince1970)
        }
        return (raw, nil)
    }
}
