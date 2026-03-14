import Testing
@testable import Distill

@Suite("PromptLoader")
struct PromptLoaderTests {
    @Test func loadDefaultSucceeds() throws {
        let prompt = try PromptLoader.loadDefault()
        #expect(prompt.contains("{{transcript}}"))
        #expect(prompt.contains("Key Takeaways"))
    }

    @Test func renderReplacesAllPlaceholders() {
        let template = "Title: {{title}}, Channel: {{channel}}, Duration: {{duration}}, Lang: {{language}}, Transcript: {{transcript}}, Frames: {{frames}}"
        let result = PromptLoader.render(
            template: template,
            title: "Test Video",
            channel: "Test Channel",
            duration: "10:00",
            transcript: "Hello world",
            frames: "",
            language: "en"
        )
        #expect(!result.contains("{{"))
        #expect(result.contains("Test Video"))
        #expect(result.contains("Test Channel"))
        #expect(result.contains("10:00"))
        #expect(result.contains("Hello world"))
    }

    @Test func framesRendersEmpty() {
        let template = "Before{{frames}}After"
        let result = PromptLoader.render(
            template: template,
            title: "",
            channel: "",
            duration: "",
            transcript: "",
            frames: "",
            language: "en"
        )
        #expect(result == "BeforeAfter")
    }
}
