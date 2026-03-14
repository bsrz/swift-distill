import Testing
@testable import Distill

@Suite("SlugGenerator")
struct SlugGeneratorTests {
    @Test func basicTitle() {
        let slug = SlugGenerator.generate(from: "How to Build a CLI in Swift")
        #expect(slug == "how-to-build-a-cli-in-swift")
    }

    @Test func unicodePreserved() {
        let slug = SlugGenerator.generate(from: "Café Résumé")
        #expect(slug.contains("café"))
        #expect(slug.contains("résumé"))
    }

    @Test func unsafeCharsRemoved() {
        let slug = SlugGenerator.generate(from: "What is C:\\Windows? A \"test\"")
        #expect(!slug.contains("\\"))
        #expect(!slug.contains(":"))
        #expect(!slug.contains("\""))
    }

    @Test func truncationAt80() {
        let longTitle = String(repeating: "word ", count: 30) // 150 chars
        let slug = SlugGenerator.generate(from: longTitle)
        #expect(slug.count <= 80)
    }

    @Test func consecutiveHyphens() {
        let slug = SlugGenerator.generate(from: "hello   ---   world")
        #expect(!slug.contains("--"))
    }

    @Test func emptyString() {
        let slug = SlugGenerator.generate(from: "")
        #expect(slug == "")
    }
}
