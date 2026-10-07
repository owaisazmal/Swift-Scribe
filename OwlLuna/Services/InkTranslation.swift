import Foundation
import Translation

/// Translating handwriting that has been read as text, with the system's translator: its languages are downloaded
/// once by iPadOS, and the words are translated on the iPad.
enum InkTranslation {
    static var isScripted: Bool {
        #if DEBUG
        return LaunchOptions.arguments.contains("-fakeTranslate")
        #else
        return false
        #endif
    }

    /// The languages offered: the ones the iPad is set to first, then the rest by name.
    static func languages() async -> [Locale.Language] {
        let supported = isScripted ? ["es", "fr", "de"].map(Locale.Language.init(identifier:)) : await LanguageAvailability().supportedLanguages
        return ordered(supported, preferred: Locale.preferredLanguages.map(Locale.Language.init(identifier:)))
    }

    static func ordered(_ supported: [Locale.Language], preferred: [Locale.Language]) -> [Locale.Language] {
        var seen = Set<String>(), first: [Locale.Language] = []
        for language in preferred {
            guard let match = supported.first(where: { $0.minimalIdentifier == language.minimalIdentifier })
                    ?? supported.first(where: { $0.languageCode == language.languageCode }), seen.insert(match.minimalIdentifier).inserted else { continue }
            first.append(match)
        }
        let rest = supported.filter { seen.insert($0.minimalIdentifier).inserted }.sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
        return first + rest
    }

    static func name(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    /// The lines that have something to translate. Text is translated line by line, so it keeps its lines and the gaps between them.
    static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Puts translated lines back where the ones they were made from stood.
    static func assemble(_ text: String, translated: [String]) -> String {
        var translated = translated[...]
        return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : translated.popFirst() ?? $0 }
            .joined(separator: "\n")
    }

    static func translate(_ text: String, with session: TranslationSession) async throws -> String {
        let lines = lines(of: text)
        guard !lines.isEmpty else { return text }
        let requests = lines.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
        let responses = try await session.translations(from: requests)
        let byLine = Dictionary(responses.map { ($0.clientIdentifier ?? "", $0.targetText) }, uniquingKeysWith: { first, _ in first })
        return assemble(text, translated: lines.indices.map { byLine[String($0)] ?? lines[$0] })
    }

    #if DEBUG
    /// `-fakeTranslate` stands this in for the translator, which a simulator doesn't have.
    static func scripted(_ text: String, into language: Locale.Language) -> String {
        let hello = ["es": "HOLA", "fr": "BONJOUR", "de": "HALLO"][language.minimalIdentifier] ?? "HELLO"
        return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : $0.uppercased().contains("HELLO") ? hello : "[\(language.minimalIdentifier)] \($0)" }
            .joined(separator: "\n")
    }
    #endif
}
