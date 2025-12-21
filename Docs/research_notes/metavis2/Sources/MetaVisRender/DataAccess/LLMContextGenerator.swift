// LLMContextGenerator.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// Generates context files for LLM consumption

import Foundation

// MARK: - LLMContextGenerator

/// Generates context files for LLM consumption
/// Output format is YAML for easy parsing and readability
public struct LLMContextGenerator {
    
    // MARK: - Properties
    
    private let store: any MetavisDataStore
    
    // MARK: - Initialization
    
    public init(store: any MetavisDataStore) {
        self.store = store
    }
    
    // MARK: - Public API
    
    /// Generate complete project context YAML for LLM
    public func generateContext() async throws -> String {
        let info = try await store.projectInfo()
        let speakers = try await store.speakers()
        let persons = try await store.persons()
        let highlights = try await store.highlights(count: 10)
        let tags = try await store.tags()
        let metadata = try await store.allMetadata()
        
        // Extract topics from transcript
        let topics = try await extractTopics()
        
        return """
        # MetaVis Project Context
        # Generated: \(ISO8601DateFormatter().string(from: Date()))
        # Use this to understand the project and translate user queries to CLI commands
        
        project:
          name: "\(escapeYAML(info.name))"
          duration: "\(info.duration.durationFormatted())"
          status: \(statusString(info.state))
          created: "\(ISO8601DateFormatter().string(from: info.createdAt))"
        
        statistics:
          speakers: \(info.speakerCount)
          named_speakers: \(info.namedSpeakerCount)
          persons: \(info.personCount)
          named_persons: \(info.namedPersonCount)
          segments: \(info.segmentCount)
          moments: \(info.momentCount)
          tags: \(info.tagCount)
        
        \(generateSpeakersSection(speakers))
        
        \(generatePersonsSection(persons))
        
        \(generateMetadataSection(metadata))
        
        \(generateTopicsSection(topics))
        
        \(generateHighlightsSection(highlights))
        
        \(generateTagsSection(tags))
        
        \(generateCommandsSection())
        
        \(generateExamplesSection(speakers: speakers, persons: persons))
        """
    }
    
    /// Generate a minimal context (for quick queries)
    public func generateMinimalContext() async throws -> String {
        let info = try await store.projectInfo()
        let speakers = try await store.speakers()
        
        return """
        # MetaVis Quick Context
        project: "\(escapeYAML(info.name))"
        duration: "\(info.duration.durationFormatted())"
        speakers:
        \(speakers.map { s in "  - \(s.displayName)" }.joined(separator: "\n"))
        
        commands:
          - "metavis find <text>"
          - "metavis clips --speaker <name>"
          - "metavis moments --emotion <type>"
          - "metavis highlights"
        """
    }
    
    /// Generate context focused on a specific time range
    public func generateTimeRangeContext(
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> String {
        let segments = try await store.segments(startTime: startTime, endTime: endTime)
        let filter = MomentFilter(startTime: startTime, endTime: endTime)
        let moments = try await store.moments(filter: filter)
        
        return """
        # MetaVis Time Range Context
        # Range: \(startTime.durationFormatted()) - \(endTime.durationFormatted())
        
        segments:
        \(segments.map { seg in
        """
          - time: "\(seg.startTime.durationFormatted()) - \(seg.endTime.durationFormatted())"
            speaker: \(seg.speakerID?.rawValue ?? "unknown")
            text: "\(escapeYAML(String(seg.transcript.prefix(200))))"
        """
        }.joined(separator: "\n"))
        
        moments:
        \(moments.map { m in
        """
          - time: "\(m.startTime.durationFormatted())"
            type: \(m.type.rawValue)
            description: "\(escapeYAML(m.description))"
        """
        }.joined(separator: "\n"))
        """
    }
    
    // MARK: - Private Helpers
    
    private func generateSpeakersSection(_ speakers: [DataSpeaker]) -> String {
        guard !speakers.isEmpty else {
            return "speakers: []"
        }
        
        return """
        speakers:
        \(speakers.map { speaker in
        """
          - id: \(speaker.id.rawValue)
            name: \(speaker.name.map { "\"\(escapeYAML($0))\"" } ?? "null")
            aliases: \(formatStringArray(speaker.aliases))
            duration: "\(speaker.totalDuration.durationFormatted())"
            segments: \(speaker.segmentCount)
            linked_person: \(speaker.linkedPersonID?.rawValue ?? "null")
        """
        }.joined(separator: "\n"))
        """
    }
    
    private func generatePersonsSection(_ persons: [DataPerson]) -> String {
        guard !persons.isEmpty else {
            return "persons: []"
        }
        
        return """
        persons:
        \(persons.map { person in
        """
          - id: \(person.id.rawValue)
            name: \(person.name.map { "\"\(escapeYAML($0))\"" } ?? "null")
            appearances: \(person.appearanceCount)
            screen_time: "\(person.totalScreenTime.durationFormatted())"
            linked_speaker: \(person.linkedSpeakerID?.rawValue ?? "null")
            global_match: \(person.globalPersonID?.rawValue ?? "null")
        """
        }.joined(separator: "\n"))
        """
    }
    
    private func generateMetadataSection(_ metadata: [MediaMetadataRecord]) -> String {
        guard !metadata.isEmpty else {
            return "# No media metadata available"
        }
        
        return """
        # Source media metadata (camera settings, etc.)
        media_sources:
        \(metadata.map { m in
        """
          - path: "\(escapeYAML(m.sourcePath))"
            camera: "\(m.cameraFullName ?? "unknown")"
            lens: "\(m.lensFullName ?? "unknown")"
            iso: \(m.iso.map { String($0) } ?? "null")
            aperture: \(m.aperture.map { String(format: "%.1f", $0) } ?? "null")
            captured: \(m.capturedAt.map { "\"\(ISO8601DateFormatter().string(from: $0))\"" } ?? "null")
            rating: \(m.rating.map { String($0) } ?? "null")
            keywords: \(formatStringArray(m.keywords))
        """
        }.joined(separator: "\n"))
        """
    }
    
    private func generateTopicsSection(_ topics: [String]) -> String {
        guard !topics.isEmpty else {
            return "detected_topics: []"
        }
        
        return """
        detected_topics:
        \(topics.map { "  - \"\(escapeYAML($0))\"" }.joined(separator: "\n"))
        """
    }
    
    private func generateHighlightsSection(_ highlights: [DetectedMoment]) -> String {
        guard !highlights.isEmpty else {
            return "highlights: []"
        }
        
        return """
        highlights:
        \(highlights.prefix(10).map { h in
        """
          - time: "\(h.startTime.durationFormatted())"
            type: \(h.type.rawValue)
            score: \(String(format: "%.2f", h.score))
            description: "\(escapeYAML(h.description))"
        """
        }.joined(separator: "\n"))
        """
    }
    
    private func generateTagsSection(_ tags: [DataTag]) -> String {
        guard !tags.isEmpty else {
            return "user_tags: []"
        }
        
        return """
        user_tags:
        \(tags.map { t in
        """
          - time: "\(t.startTime.durationFormatted()) - \(t.endTime.durationFormatted())"
            label: "\(escapeYAML(t.label))"
            note: \(t.note.map { "\"\(escapeYAML($0))\"" } ?? "null")
        """
        }.joined(separator: "\n"))
        """
    }
    
    private func generateCommandsSection() -> String {
        return """
        # Available CLI commands
        available_commands:
          discovery:
            - "metavis info"
            - "metavis speakers"
            - "metavis persons"
            - "metavis timeline"
            - "metavis status"
          
          query:
            - "metavis find <text> [--speaker NAME] [--emotion TYPE]"
            - "metavis clips [--speaker NAME] [--min-duration SEC] [--max-duration SEC]"
            - "metavis moments [--type TYPE] [--emotion TYPE] [--threshold 0.0-1.0]"
            - "metavis highlights [--count N]"
          
          metadata_query:
            - "metavis find-metadata [--camera NAME] [--lens NAME]"
            - "metavis find-metadata [--iso MIN-MAX] [--aperture MIN-MAX]"
            - "metavis find-metadata [--rating N+] [--keyword TAG]"
            - "metavis find-metadata [--date-from YYYY-MM-DD] [--date-to YYYY-MM-DD]"
            - "metavis metadata <file>"
          
          mutation:
            - "metavis identify <ID> --name NAME"
            - "metavis link <SPEAKER_ID> <PERSON_ID>"
            - "metavis tag <START>-<END> --label LABEL [--note TEXT]"
            - "metavis global add <PERSON_ID>"
          
          export:
            - "metavis export --format json"
            - "metavis export --format edl [--speaker NAME]"
            - "metavis export --format srt"
            - "metavis export --format csv"
        """
    }
    
    private func generateExamplesSection(speakers: [DataSpeaker], persons: [DataPerson]) -> String {
        // Use actual speaker/person names if available
        let speakerExample = speakers.first { $0.name != nil }?.name ?? "Sarah"
        let personExample = persons.first { $0.name != nil }?.name ?? "John"
        let speakerIDExample = speakers.first?.id.rawValue ?? "SPEAKER_00"
        let personIDExample = persons.first?.id.rawValue ?? "PERSON_001"
        
        return """
        # Translation examples for natural language → CLI
        translation_examples:
          # Discovery queries
          - user: "What is this project about?"
            command: "metavis info"
          
          - user: "Who are the speakers?"
            command: "metavis speakers"
          
          - user: "Who appears in the video?"
            command: "metavis persons"
          
          # Text search
          - user: "Find when they talk about budget"
            command: "metavis find 'budget'"
          
          - user: "Show me when \(speakerExample) mentions the deadline"
            command: "metavis find 'deadline' --speaker '\(speakerExample)'"
          
          - user: "Find excited moments"
            command: "metavis moments --emotion excited"
          
          # Clip queries
          - user: "Get all clips under 30 seconds"
            command: "metavis clips --max-duration 30"
          
          - user: "Show me \(speakerExample)'s speaking parts"
            command: "metavis clips --speaker '\(speakerExample)'"
          
          - user: "What are the highlights?"
            command: "metavis highlights --count 10"
          
          # Metadata queries
          - user: "Find all low-light shots"
            command: "metavis find-metadata --iso 1600-12800"
          
          - user: "Show me shallow depth of field clips"
            command: "metavis find-metadata --aperture 1.4-2.8"
          
          - user: "Find clips shot on Sony camera"
            command: "metavis find-metadata --camera 'Sony'"
          
          - user: "Show 4-star rated footage"
            command: "metavis find-metadata --rating 4"
          
          - user: "What camera settings were used?"
            command: "metavis metadata source.mov --camera"
          
          # Mutations
          - user: "That's \(speakerExample)"
            command: "metavis identify \(speakerIDExample) --name '\(speakerExample)'"
          
          - user: "Link \(speakerExample)'s voice to the person on screen"
            command: "metavis link \(speakerIDExample) \(personIDExample)"
          
          - user: "Mark this as a key moment"
            command: "metavis tag 01:23-01:45 --label 'key_moment'"
          
          - user: "Remember \(personExample) for future videos"
            command: "metavis global add \(personIDExample)"
          
          # Export
          - user: "Export for Final Cut"
            command: "metavis export --format fcpxml"
          
          - user: "Get \(speakerExample)'s parts for editing"
            command: "metavis export --format edl --speaker '\(speakerExample)'"
          
          - user: "Generate subtitles"
            command: "metavis export --format srt"
          
          - user: "Export everything as JSON"
            command: "metavis export --format json"
        """
    }
    
    /// Extract topics from transcript using simple keyword analysis
    private func extractTopics() async throws -> [String] {
        let segments = try await store.allSegments()
        
        // Combine all transcripts
        let fullText = segments.map { $0.transcript }.joined(separator: " ").lowercased()
        
        // Simple topic extraction: find frequently occurring noun phrases
        // In a real implementation, this would use NLP
        var wordCounts: [String: Int] = [:]
        
        let words = fullText.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { $0.count > 4 }  // Only words longer than 4 chars
        
        // Common stop words to filter out
        let stopWords = Set([
            "about", "above", "after", "again", "against", "all", "also", "and",
            "any", "are", "aren't", "as", "at", "be", "because", "been", "before",
            "being", "below", "between", "both", "but", "by", "can't", "cannot",
            "could", "couldn't", "did", "didn't", "do", "does", "doesn't", "doing",
            "don't", "down", "during", "each", "few", "for", "from", "further",
            "had", "hadn't", "has", "hasn't", "have", "haven't", "having", "he",
            "he'd", "he'll", "he's", "her", "here", "here's", "hers", "herself",
            "him", "himself", "his", "how", "how's", "i", "i'd", "i'll", "i'm",
            "i've", "if", "in", "into", "is", "isn't", "it", "it's", "its",
            "itself", "just", "let's", "like", "make", "more", "most", "much",
            "must", "my", "myself", "no", "nor", "not", "of", "off", "on",
            "once", "only", "or", "other", "ought", "our", "ours", "ourselves",
            "out", "over", "own", "really", "right", "same", "say", "she",
            "she'd", "she'll", "she's", "should", "shouldn't", "so", "some",
            "such", "than", "that", "that's", "the", "their", "theirs", "them",
            "themselves", "then", "there", "there's", "these", "they", "they'd",
            "they'll", "they're", "they've", "think", "this", "those", "through",
            "to", "too", "under", "until", "up", "very", "was", "wasn't", "we",
            "we'd", "we'll", "we're", "we've", "were", "weren't", "what", "what's",
            "when", "when's", "where", "where's", "which", "while", "who", "who's",
            "whom", "why", "why's", "will", "with", "won't", "would", "wouldn't",
            "you", "you'd", "you'll", "you're", "you've", "your", "yours",
            "yourself", "yourselves", "going", "know", "want", "yeah", "okay",
            "thing", "things", "something", "actually", "really", "getting"
        ])
        
        for word in words {
            if !stopWords.contains(word) {
                wordCounts[word, default: 0] += 1
            }
        }
        
        // Get top topics
        let sortedTopics = wordCounts.sorted { $0.value > $1.value }
        return Array(sortedTopics.prefix(10).map { $0.key })
    }
    
    private func statusString(_ state: IngestionState) -> String {
        switch state {
        case .notStarted: return "not_started"
        case .inProgress: return "in_progress"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }
    
    private func escapeYAML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
    
    private func formatStringArray(_ array: [String]) -> String {
        if array.isEmpty {
            return "[]"
        }
        return "[\(array.map { "\"\(escapeYAML($0))\"" }.joined(separator: ", "))]"
    }
}

// MARK: - Convenience Extensions

extension LLMContextGenerator {
    
    /// Save context to a file
    public func saveContext(to url: URL) async throws {
        let context = try await generateContext()
        try context.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Generate and print context to stdout
    public func printContext() async throws {
        let context = try await generateContext()
        print(context)
    }
}
