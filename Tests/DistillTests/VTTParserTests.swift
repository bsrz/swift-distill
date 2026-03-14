import Testing
@testable import Distill

@Suite("VTTParser")
struct VTTParserTests {
    @Test func simpleVTT() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:05.000
        Hello, welcome to the video.

        00:00:05.000 --> 00:00:10.000
        Today we'll talk about Swift.
        """
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.segments.count == 2)
        #expect(transcript.segments[0].text == "Hello, welcome to the video.")
        #expect(transcript.segments[0].startTime == 0)
        #expect(transcript.segments[0].endTime == 5)
    }

    @Test func autoCaptionWithTags() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:05.000
        <c> Hello</c><c> welcome</c><c> to</c><c> the</c><c> video</c>
        """
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments[0].text == "Hello welcome to the video")
    }

    @Test func overlappingCueDedup() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:03.000
        Hello world

        00:00:01.000 --> 00:00:04.000
        Hello world

        00:00:03.000 --> 00:00:06.000
        Something new
        """
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.segments.count == 2)
    }

    @Test func positionAttributes() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:05.000 position:10% align:start
        Hello world
        """
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments[0].text == "Hello world")
    }

    @Test func emptyVTT() {
        let vtt = "WEBVTT\n\n"
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.segments.isEmpty)
    }

    @Test func fullTextJoining() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:03.000
        Hello

        00:00:03.000 --> 00:00:06.000
        World
        """
        let transcript = VTTParser.parse(vtt)
        #expect(transcript.fullText == "Hello World")
    }
}
