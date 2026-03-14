import Testing
@testable import Distill

@Suite("URLValidator")
struct URLValidatorTests {
    @Test func validLongURL() throws {
        let id = try URLValidator.validate("https://www.youtube.com/watch?v=jNQXAC9IVRw")
        #expect(id == "jNQXAC9IVRw")
    }

    @Test func validShortURL() throws {
        let id = try URLValidator.validate("https://youtu.be/jNQXAC9IVRw")
        #expect(id == "jNQXAC9IVRw")
    }

    @Test func validURLWithExtraParams() throws {
        let id = try URLValidator.validate("https://www.youtube.com/watch?v=jNQXAC9IVRw&t=120&list=PLxyz")
        #expect(id == "jNQXAC9IVRw")
    }

    @Test func validURLWithoutWWW() throws {
        let id = try URLValidator.validate("https://youtube.com/watch?v=jNQXAC9IVRw")
        #expect(id == "jNQXAC9IVRw")
    }

    @Test func httpFails() {
        #expect(throws: DistillError.self) {
            try URLValidator.validate("not-a-url")
        }
    }

    @Test func nonYouTubeFails() {
        #expect(throws: DistillError.self) {
            try URLValidator.validate("https://vimeo.com/12345")
        }
    }

    @Test func missingIDFails() {
        #expect(throws: DistillError.self) {
            try URLValidator.validate("https://www.youtube.com/watch?v=")
        }
    }

    @Test func videoIDExtraction() {
        #expect(URLValidator.extractVideoID("https://youtu.be/jNQXAC9IVRw") == "jNQXAC9IVRw")
        #expect(URLValidator.extractVideoID("invalid") == nil)
    }

    @Test func shortsURL() throws {
        let id = try URLValidator.validate("https://www.youtube.com/shorts/jNQXAC9IVRw")
        #expect(id == "jNQXAC9IVRw")
    }
}
