import Foundation

struct PageMatch: Equatable, Sendable {
    let time: TimeInterval
    let confidence: Double
    let wordRange: Range<Int>
    let snippet: String
}

enum PageMatcher {
    static func match(
        ocr: String,
        transcript: [TranscriptWord],
        shingleSize: Int = 5,
        minimumConfidence: Double = 0.4
    ) -> PageMatch? {
        let haystack = flattenedTokens(of: transcript)
        let needle = normalize(ocr)
        guard shingleSize > 0,
              haystack.tokens.count >= shingleSize,
              needle.count >= shingleSize
        else { return nil }

        var index: [String: [Int]] = [:]
        for i in 0...(haystack.tokens.count - shingleSize) {
            let key = haystack.tokens[i..<i + shingleSize].joined(separator: " ")
            index[key, default: []].append(haystack.owners[i])
        }

        var votes: [Int: Int] = [:]
        var hits = 0
        for i in 0...(needle.count - shingleSize) {
            let key = needle[i..<i + shingleSize].joined(separator: " ")
            if let owners = index[key] {
                for owner in owners {
                    votes[owner, default: 0] += 1
                    hits += 1
                }
            }
        }
        guard hits > 0 else { return nil }

        var clusters: [[Int]] = []
        var current: [Int] = []
        let clusterGap = shingleSize * 3
        for wordIndex in votes.keys.sorted() {
            if let last = current.last, wordIndex - last <= clusterGap {
                current.append(wordIndex)
            } else {
                if !current.isEmpty { clusters.append(current) }
                current = [wordIndex]
            }
        }
        if !current.isEmpty { clusters.append(current) }

        var best = clusters[0]
        var bestWeight = weight(of: best, votes: votes)
        for cluster in clusters.dropFirst() {
            let candidateWeight = weight(of: cluster, votes: votes)
            if candidateWeight > bestWeight {
                best = cluster
                bestWeight = candidateWeight
            }
        }

        let confidence = Double(bestWeight) / Double(needle.count - shingleSize + 1) * Double(bestWeight) / Double(hits)
        guard confidence >= minimumConfidence else { return nil }

        let first = best[0]
        let last = min(best[best.count - 1] + shingleSize, transcript.count)
        let snippet = transcript[first..<last].map(\.text).joined(separator: " ")
        return PageMatch(
            time: transcript[first].start,
            confidence: confidence,
            wordRange: first..<last,
            snippet: snippet)
    }

    static func normalize(_ text: String) -> [String] {
        var word: [Character] = []
        var words: [String] = []
        for character in text.lowercased() {
            if character.isLetter {
                word.append(character)
            } else if !word.isEmpty {
                words.append(String(word))
                word.removeAll()
            }
        }
        if !word.isEmpty { words.append(String(word)) }
        return words
    }

    private struct Flattened: Sendable {
        var tokens: [String]
        var owners: [Int]
    }

    private static func flattenedTokens(of transcript: [TranscriptWord]) -> Flattened {
        var tokens: [String] = []
        var owners: [Int] = []
        for (i, word) in transcript.enumerated() {
            let parts = normalize(word.text)
            tokens.append(contentsOf: parts)
            owners.append(contentsOf: repeatElement(i, count: parts.count))
        }
        return Flattened(tokens: tokens, owners: owners)
    }

    private static func weight(of cluster: [Int], votes: [Int: Int]) -> Int {
        cluster.reduce(0) { $0 + (votes[$1] ?? 0) }
    }
}
