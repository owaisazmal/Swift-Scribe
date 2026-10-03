import XCTest
@testable import NotesApp

/// Translating handwriting read as text: which languages are offered first, and how the text keeps its lines.
final class TranslateTests: XCTestCase {
    private func language(_ identifier: String) -> Locale.Language { Locale.Language(identifier: identifier) }

    func testTheLanguagesTheIPadIsSetToComeFirst() {
        let supported = ["de", "en", "es", "fr", "ja", "pt-BR"].map(language)
        let ordered = InkTranslation.ordered(supported, preferred: [language("fr-CA"), language("en-GB"), language("sv")])
        XCTAssertEqual(ordered.prefix(2).map(\.minimalIdentifier), ["fr", "en"], "a regional setting finds its language; one that isn't supported is left out")
        XCTAssertEqual(ordered.count, supported.count, "every supported language is offered once")
        XCTAssertEqual(Set(ordered.map(\.minimalIdentifier)), Set(supported.map(\.minimalIdentifier)))
        let rest = ordered.dropFirst(2).map(InkTranslation.name(of:))
        XCTAssertEqual(rest, rest.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "the rest go by name")
    }

    func testTranslatedTextKeepsItsLines() {
        let text = "First line\n\n  \nSecond line\n"
        XCTAssertEqual(InkTranslation.lines(of: text), ["First line", "Second line"], "blank lines aren't sent to be translated")
        XCTAssertEqual(InkTranslation.assemble(text, translated: ["Première ligne", "Deuxième ligne"]), "Première ligne\n\n  \nDeuxième ligne\n")
        XCTAssertEqual(InkTranslation.assemble(text, translated: ["Première ligne"]), "Première ligne\n\n  \nSecond line\n", "a line that didn't come back stays as it was")
        XCTAssertEqual(InkTranslation.lines(of: " \n"), [])
    }

    func testTheStandInTranslatesTheSeededHandwriting() {
        XCTAssertEqual(InkTranslation.scripted("HELLO", into: language("fr")), "BONJOUR")
        XCTAssertEqual(InkTranslation.scripted("Hello\n\nnotes", into: language("es")), "HOLA\n\n[es] notes")
    }
}
