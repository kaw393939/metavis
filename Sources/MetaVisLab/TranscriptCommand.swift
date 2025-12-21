import Foundation
import AVFoundation
import MetaVisCore
import MetaVisExport

enum TranscriptCommand {
    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" || args.first == nil {
            print(help)
            return
        }

        switch args.first {
        case "generate":
            try await Generate.run(args: Array(args.dropFirst()))
        default:
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown transcript subcommand: \(args.first ?? "")"])
        }
    }

    private enum Generate {
        struct Options {
            var inputMovieURL: URL
            var outputDirURL: URL
            var allowLarge: Bool

            var startSeconds: Double
            var maxSeconds: Double
            var language: String?
            var writeAdjacentCaptions: Bool
        }

        static func run(args: [String]) async throws {
            if args.first == "--help" || args.first == "-h" || args.contains("--help") || args.contains("-h") {
                print(help)
                return
            }

            let options = try parseArgs(args)
            try enforceLargeAssetPolicy(inputURL: options.inputMovieURL, allowLarge: options.allowLarge)

            try FileManager.default.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

            let env = ProcessInfo.processInfo.environment
            guard let whisperCppBin = env["WHISPERCPP_BIN"], !whisperCppBin.isEmpty,
                  let whisperCppModel = env["WHISPERCPP_MODEL"], !whisperCppModel.isEmpty else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing required environment. Set WHISPERCPP_BIN and WHISPERCPP_MODEL."]
                )
            }

            let whisperURL = URL(fileURLWithPath: whisperCppBin)
            guard FileManager.default.fileExists(atPath: whisperURL.path) else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "WHISPERCPP_BIN does not exist: \(whisperURL.path)"]
                )
            }
            guard FileManager.default.isExecutableFile(atPath: whisperURL.path) else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "WHISPERCPP_BIN is not executable: \(whisperURL.path)"]
                )
            }

            let whisperModelURL = URL(fileURLWithPath: whisperCppModel)
            guard FileManager.default.fileExists(atPath: whisperModelURL.path) else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "WHISPERCPP_MODEL does not exist: \(whisperModelURL.path)"]
                )
            }

            let tempDir = options.outputDirURL.appendingPathComponent("_whisper_tmp", isDirectory: true)
            try? FileManager.default.removeItem(at: tempDir)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let (transcribeInputURL, offsetTicks) = try await makeOptionalTrimmedAudio(
                inputMovieURL: options.inputMovieURL,
                startSeconds: options.startSeconds,
                maxSeconds: options.maxSeconds,
                tempDir: tempDir
            )

            let outputStem = tempDir.appendingPathComponent("whispercpp")
            let expectedJSON = URL(fileURLWithPath: outputStem.path + ".json")

            let stdoutURL = options.outputDirURL.appendingPathComponent("whispercpp.stdout.txt")
            let stderrURL = options.outputDirURL.appendingPathComponent("whispercpp.stderr.txt")

            // whisper.cpp JSON (full) + word-level segmentation:
            // -ojf: output JSON (full)
            // -ml 1: force word-level segmentation (so each segment is effectively a word)
            // -of <stem>: output filename stem (writes <stem>.json)
            var whisperArgs: [String] = [
                "-m", whisperModelURL.path,
                "-f", transcribeInputURL.path,
                "-ml", "1",
                "-ojf",
                "-of", outputStem.path
            ]
            if let lang = options.language, !lang.isEmpty {
                whisperArgs += ["-l", lang]
            }

            try runProcess(whisperURL.path, whisperArgs, stdoutURL: stdoutURL, stderrURL: stderrURL)

            let jsonOut: URL
            if FileManager.default.fileExists(atPath: expectedJSON.path) {
                jsonOut = expectedJSON
            } else {
                let jsons = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
                let candidates = jsons.filter { $0.pathExtension.lowercased() == "json" }
                if candidates.count == 1 {
                    jsonOut = candidates[0]
                } else {
                    throw NSError(
                        domain: "MetaVisLab",
                        code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "Transcriber did not produce expected JSON output. Expected \(expectedJSON.lastPathComponent). Found \(candidates.map { $0.lastPathComponent }.joined(separator: ", "))"]
                    )
                }
            }

            let parsed = try parseWhisperCppJSON(url: jsonOut)
            let words = parsed.words
                .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { w -> TimedWord in
                    let token = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    let startTicks = secondsToTicks(w.startSeconds) + offsetTicks
                    let endTicks = secondsToTicks(w.endSeconds) + offsetTicks
                    return TimedWord(text: token, startTicks: startTicks, endTicks: endTicks)
                }
                .filter { $0.endTicks >= $0.startTicks }

            let wordsJSONLURL = options.outputDirURL.appendingPathComponent("transcript.words.v1.jsonl")
            try writeWordsJSONL(to: wordsJSONLURL, words: words)

            let captionsURL = options.outputDirURL.appendingPathComponent("captions.vtt")
            let cues = cuesFromWords(words)
            try await CaptionSidecarWriter.writeWebVTT(to: captionsURL, cues: cues)

            if options.writeAdjacentCaptions {
                let adjacentURL = options.inputMovieURL
                    .deletingPathExtension()
                    .appendingPathExtension("captions.vtt")
                try await CaptionSidecarWriter.writeWebVTT(to: adjacentURL, cues: cues)
            }

            let durationSeconds = await probeDurationSeconds(url: options.inputMovieURL)
            let summaryURL = options.outputDirURL.appendingPathComponent("transcript.summary.v1.json")
            let summary = TranscriptSummaryV1(
                input: options.inputMovieURL.lastPathComponent,
                durationSeconds: durationSeconds,
                language: parsed.language,
                tool: .init(name: whisperURL.lastPathComponent, version: nil, model: whisperModelURL.lastPathComponent),
                wordCount: words.count
            )
            try writeSummaryJSON(to: summaryURL, summary: summary)

            print("transcript generate: wrote \(wordsJSONLURL.lastPathComponent), \(summaryURL.lastPathComponent), \(captionsURL.lastPathComponent)")
        }

        private struct TimedWord {
            var text: String
            var startTicks: Int64
            var endTicks: Int64
        }

        private struct WhisperParsedWord {
            var word: String
            var startSeconds: Double
            var endSeconds: Double
        }

        private struct WhisperParsed {
            var language: String?
            var words: [WhisperParsedWord]
        }

        private static func parseWhisperCppJSON(url: URL) throws -> WhisperParsed {
            // whisper.cpp `-ojf` format varies across versions/forks, so we decode a tolerant subset.
            struct Root: Decodable {
                var result: Result?
                var segments: [Segment]?
                var transcription: [TranscriptionItem]?

                struct Result: Decodable {
                    var language: String?
                }

                struct TranscriptionItem: Decodable {
                    var text: String?
                    var offsets: Segment.Offsets?
                    var t0: Int?
                    var t1: Int?
                }
            }

            struct Segment: Decodable {
                var text: String?
                var t0: Int?
                var t1: Int?
                var offsets: Offsets?
                var words: [Word]?

                struct Offsets: Decodable {
                    var from: Int?
                    var to: Int?
                }

                struct Word: Decodable {
                    var word: String?
                    var text: String?
                    var t0: Int?
                    var t1: Int?
                    var offsets: Offsets?
                }
            }

            func secondsFromOffsetsOrT0T1(offsets: Segment.Offsets?, t0: Int?, t1: Int?) -> (start: Double, end: Double)? {
                if let fromMS = offsets?.from, let toMS = offsets?.to {
                    let start = Double(fromMS) / 1000.0
                    let end = Double(toMS) / 1000.0
                    return (start: start, end: end)
                }
                if let t0, let t1 {
                    // whisper.cpp C API uses 10ms units.
                    let start = Double(t0) / 100.0
                    let end = Double(t1) / 100.0
                    return (start: start, end: end)
                }
                return nil
            }

            func appendWords(into out: inout [WhisperParsedWord], rawText: String, start: Double, end: Double) {
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                // If the segment contains multiple whitespace-separated tokens, split deterministically.
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !parts.isEmpty else { return }
                if parts.count == 1 {
                    out.append(.init(word: parts[0], startSeconds: start, endSeconds: max(start, end)))
                    return
                }

                let total = max(0.0, end - start)
                let step = total / Double(parts.count)
                for (idx, p) in parts.enumerated() {
                    let s = start + (Double(idx) * step)
                    let e = (idx == parts.count - 1) ? end : (start + (Double(idx + 1) * step))
                    out.append(.init(word: p, startSeconds: s, endSeconds: max(s, e)))
                }
            }

            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(Root.self, from: data)

            var out: [WhisperParsedWord] = []

            // Common newer -ojf shape: top-level `transcription` is already word-like.
            if let transcription = root.transcription, !transcription.isEmpty {
                out.reserveCapacity(transcription.count)
                for item in transcription {
                    let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    guard let timing = secondsFromOffsetsOrT0T1(offsets: item.offsets, t0: item.t0, t1: item.t1) else { continue }
                    appendWords(into: &out, rawText: text, start: timing.start, end: timing.end)
                }

                return WhisperParsed(language: root.result?.language, words: out)
            }

            if let segments = root.segments {
                out.reserveCapacity(2048)
                for seg in segments {
                    if let words = seg.words, !words.isEmpty {
                        for w in words {
                            let text = (w.word ?? w.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            let timing = secondsFromOffsetsOrT0T1(offsets: w.offsets, t0: w.t0, t1: w.t1)
                                ?? secondsFromOffsetsOrT0T1(offsets: seg.offsets, t0: seg.t0, t1: seg.t1)
                            guard let timing else { continue }
                            appendWords(into: &out, rawText: text, start: timing.start, end: timing.end)
                        }
                        continue
                    }

                    let text = (seg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    guard let timing = secondsFromOffsetsOrT0T1(offsets: seg.offsets, t0: seg.t0, t1: seg.t1) else { continue }
                    appendWords(into: &out, rawText: text, start: timing.start, end: timing.end)
                }
            }

            return WhisperParsed(language: root.result?.language, words: out)
        }

        private static func secondsToTicks(_ seconds: Double) -> Int64 {
            // Contract: ticks = round(seconds * 60000)
            let scaled = (seconds * 60000.0).rounded()
            if !scaled.isFinite { return 0 }
            if scaled > Double(Int64.max) { return Int64.max }
            if scaled < Double(Int64.min) { return Int64.min }
            return Int64(scaled)
        }

        private static func cuesFromWords(_ words: [TimedWord]) -> [CaptionCue] {
            guard !words.isEmpty else { return [] }

            var cues: [CaptionCue] = []
            cues.reserveCapacity(max(8, words.count / 8))

            var currentWords: [TimedWord] = []
            currentWords.reserveCapacity(16)

            func flushCue() {
                guard let first = currentWords.first, let last = currentWords.last else { return }
                let start = Double(first.startTicks) / 60000.0
                let end = max(start, Double(last.endTicks) / 60000.0)
                let text = currentWords.map { $0.text }.joined(separator: " ")
                cues.append(CaptionCue(startSeconds: start, endSeconds: end, text: text, speaker: nil))
                currentWords.removeAll(keepingCapacity: true)
            }

            var lastEndTicks: Int64? = nil
            for w in words {
                if currentWords.isEmpty {
                    currentWords.append(w)
                    lastEndTicks = w.endTicks
                    continue
                }

                let firstStartTicks = currentWords.first?.startTicks ?? w.startTicks
                let cueDurationTicks = max(Int64(0), w.endTicks - firstStartTicks)
                let cueDurationSeconds = Double(cueDurationTicks) / 60000.0

                let gapTicks = (lastEndTicks ?? w.startTicks) > w.startTicks ? 0 : (w.startTicks - (lastEndTicks ?? w.startTicks))
                let gapSeconds = Double(gapTicks) / 60000.0

                let tooLong = cueDurationSeconds >= 4.0
                let tooManyWords = currentWords.count >= 12
                let bigGap = gapSeconds >= 0.8
                let endsSentence = (currentWords.last?.text.last).map { ".!?".contains($0) } ?? false

                if tooLong || tooManyWords || bigGap || endsSentence {
                    flushCue()
                }

                currentWords.append(w)
                lastEndTicks = w.endTicks
            }

            flushCue()
            return cues
        }

        private static func writeWordsJSONL(to url: URL, words: [TimedWord]) throws {
            var ordinalWithinRange: [String: Int] = [:]
            ordinalWithinRange.reserveCapacity(256)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            var out = Data()
            out.reserveCapacity(words.count * 120)

            for w in words {
                let key = "\(w.startTicks)_\(w.endTicks)"
                let current = (ordinalWithinRange[key] ?? 0) + 1
                ordinalWithinRange[key] = current

                let wordId = "w_\(w.startTicks)_\(w.endTicks)_\(current)"

                let record = MetaVisCore.TranscriptWordV1(
                    schema: "transcript.word.v1",
                    wordId: wordId,
                    word: w.text,
                    confidence: 1.0,
                    sourceTimeTicks: w.startTicks,
                    sourceTimeEndTicks: w.endTicks,
                    speakerId: nil,
                    speakerLabel: nil,
                    timelineTimeTicks: w.startTicks,
                    timelineTimeEndTicks: w.endTicks,
                    clipId: nil,
                    segmentId: nil
                )

                let line = try encoder.encode(record)
                out.append(line)
                out.append(0x0A) // \n
            }

            try out.write(to: url, options: [.atomic])
        }

        private struct TranscriptSummaryV1: Codable {
            var schema: String = "transcript.summary.v1"
            var input: String
            var durationSeconds: Double
            var language: String?
            var tool: Tool
            var wordCount: Int

            struct Tool: Codable {
                var name: String
                var version: String?
                var model: String
            }
        }

        private static func writeSummaryJSON(to url: URL, summary: TranscriptSummaryV1) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)
            try data.write(to: url, options: [.atomic])
        }

        private static func runProcess(_ executable: String, _ args: [String], stdoutURL: URL, stderrURL: URL) throws {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            proc.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            try outData.write(to: stdoutURL, options: [.atomic])
            try errData.write(to: stderrURL, options: [.atomic])

            if proc.terminationStatus != 0 {
                let msg = "Process failed: \(URL(fileURLWithPath: executable).lastPathComponent) (status=\(proc.terminationStatus)). See \(stdoutURL.lastPathComponent) and \(stderrURL.lastPathComponent)."
                throw NSError(domain: "MetaVisLab", code: 11, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }

        private static func makeOptionalTrimmedAudio(
            inputMovieURL: URL,
            startSeconds: Double,
            maxSeconds: Double,
            tempDir: URL
        ) async throws -> (url: URL, offsetTicks: Int64) {
            let start = max(0.0, startSeconds)
            let maxDur = max(0.0, maxSeconds)
            let needsTrim = (start > 0.0) || (maxDur > 0.0)

            let offsetTicks = secondsToTicks(start)
            guard needsTrim else { return (inputMovieURL, offsetTicks) }

            let outURL = tempDir.appendingPathComponent("transcript_clip_16k_mono.wav")

            var ffmpegArgs: [String] = ["ffmpeg", "-y"]
            if start > 0.0 {
                ffmpegArgs += ["-ss", String(start)]
            }
            if maxDur > 0.0 {
                ffmpegArgs += ["-t", String(maxDur)]
            }
            ffmpegArgs += [
                "-i", inputMovieURL.path,
                "-vn",
                "-ac", "1",
                "-ar", "16000",
                outURL.path
            ]

            let ffOut = tempDir.appendingPathComponent("ffmpeg.stdout.txt")
            let ffErr = tempDir.appendingPathComponent("ffmpeg.stderr.txt")
            try runProcess("/usr/bin/env", ffmpegArgs, stdoutURL: ffOut, stderrURL: ffErr)

            guard FileManager.default.fileExists(atPath: outURL.path) else {
                throw NSError(domain: "MetaVisLab", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to trim audio via ffmpeg"])
            }

            return (outURL, offsetTicks)
        }

        private static func probeDurationSeconds(url: URL) async -> Double {
            let asset = AVURLAsset(url: url)
            do {
                let dur = try await asset.load(.duration)
                return max(0.0, dur.seconds)
            } catch {
                return 0.0
            }
        }

        private static func absoluteFileURL(_ path: String) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }

        private static func enforceLargeAssetPolicy(inputURL: URL, allowLarge: Bool) throws {
            let name = inputURL.lastPathComponent.lowercased()

            let sizeBytes: Int64
            do {
                let values = try inputURL.resourceValues(forKeys: [.fileSizeKey])
                sizeBytes = Int64(values.fileSize ?? 0)
            } catch {
                sizeBytes = 0
            }

            let isLikelyLarge = (sizeBytes >= 1_000_000_000) || name.contains("keith_talk")
            if isLikelyLarge && !allowLarge {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Refusing to process large asset (\(name), \(sizeBytes) bytes) without --allow-large."]
                )
            }
        }

        private static func parseArgs(_ args: [String]) throws -> Options {
            var inputPath: String?
            var outDir: String?
            var allowLarge = false

            var startSeconds: Double = 0
            var maxSeconds: Double = 0
            var language: String?
            var writeAdjacentCaptions = true

            var i = 0
            while i < args.count {
                switch args[i] {
                case "--input":
                    i += 1
                    inputPath = (i < args.count) ? args[i] : nil
                case "--out":
                    i += 1
                    outDir = (i < args.count) ? args[i] : nil
                case "--allow-large":
                    allowLarge = true
                case "--start-seconds":
                    i += 1
                    if i < args.count { startSeconds = Double(args[i]) ?? 0 }
                case "--max-seconds":
                    i += 1
                    if i < args.count { maxSeconds = Double(args[i]) ?? 0 }
                case "--language":
                    i += 1
                    language = (i < args.count) ? args[i] : nil
                case "--write-adjacent-captions":
                    i += 1
                    if i < args.count {
                        let raw = args[i].lowercased()
                        writeAdjacentCaptions = (raw == "true" || raw == "1" || raw == "yes")
                    }
                default:
                    break
                }
                i += 1
            }

            guard let inputPath else {
                print(help)
                throw NSError(domain: "MetaVisLab", code: 9, userInfo: [NSLocalizedDescriptionKey: "Missing --input <movie>"])
            }
            guard let outDir else {
                print(help)
                throw NSError(domain: "MetaVisLab", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing --out <dir>"])
            }

            return Options(
                inputMovieURL: absoluteFileURL(inputPath),
                outputDirURL: absoluteFileURL(outDir),
                allowLarge: allowLarge,
                startSeconds: max(0.0, startSeconds),
                maxSeconds: max(0.0, maxSeconds),
                language: language,
                writeAdjacentCaptions: writeAdjacentCaptions
            )
        }

        private static let help = """
        transcript

        Generates a local word-level transcript JSONL + VTT captions for a movie.

        Required env:
                    WHISPERCPP_BIN=/absolute/path/to/whisper-cli
                    WHISPERCPP_MODEL=/absolute/path/to/ggml-<model>.bin

        Usage:
          MetaVisLab transcript generate --input <movie.mov> --out <dir> [--start-seconds <s>] [--max-seconds <s>] [--language <code>] [--write-adjacent-captions true|false] [--allow-large]

        Output (in --out):
          transcript.words.v1.jsonl
          transcript.summary.v1.json
          captions.vtt

        Notes:
          If --write-adjacent-captions=true (default), writes <input_stem>.captions.vtt next to the input movie.
        """
    }

    private static let help = """
    transcript

    Usage:
      MetaVisLab transcript generate --input <movie.mov> --out <dir> [--start-seconds <s>] [--max-seconds <s>] [--language <code>] [--write-adjacent-captions true|false] [--allow-large]
    """
}
