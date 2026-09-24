import XCTest
@testable import LlamaScopeProxyCore

final class HTTPRequestHeadTests: XCTestCase {
    private let sample = [
        "POST /api/chat?stream=true HTTP/1.1",
        "Host: 127.0.0.1:11435",
        "Content-Type: application/json",
        "Content-Length: 42",
        "Connection: keep-alive",
        "Accept-Encoding: gzip",
    ].joined(separator: "\r\n")

    func testItReadsTheRequestLine() {
        let head = HTTPRequestHead.parse(sample)
        XCTAssertEqual(head?.method, "POST")
        XCTAssertEqual(head?.target, "/api/chat?stream=true")
        XCTAssertEqual(head?.path, "/api/chat")
    }

    func testTheHeaderNameIsMatchedRegardlessOfCase() {
        let head = HTTPRequestHead.parse(sample)
        XCTAssertEqual(head?.value(for: "content-type"), "application/json")
        XCTAssertEqual(head?.value(for: "CONTENT-TYPE"), "application/json")
        XCTAssertNil(head?.value(for: "Authorization"))
    }

    func testContentLengthDefaultsToZeroRatherThanToNil() {
        // Żądanie bez ciała ma ciało zerowej długości — brak nagłówka nie
        // jest tu niewiadomą, tylko zerem.
        let head = HTTPRequestHead.parse("GET /api/tags HTTP/1.1\r\nHost: x")
        XCTAssertEqual(head?.contentLength, 0)
        XCTAssertEqual(HTTPRequestHead.parse(sample)?.contentLength, 42)
    }

    func testChunkedIsRecognisedInAListOfEncodings() {
        let head = HTTPRequestHead.parse(
            "POST /api/chat HTTP/1.1\r\nTransfer-Encoding: gzip, chunked"
        )
        XCTAssertEqual(head?.isChunked, true)
        XCTAssertEqual(HTTPRequestHead.parse(sample)?.isChunked, false)
    }

    func testHopByHopHeadersAreNotPassedOn() {
        let forwarded = HTTPRequestHead.parse(sample)?.forwardableHeaders.map(\.name) ?? []
        XCTAssertEqual(forwarded, ["Host", "Content-Type", "Accept-Encoding"])
        XCTAssertFalse(forwarded.contains("Connection"))
        XCTAssertFalse(forwarded.contains("Content-Length"))
    }

    func testSomethingThatIsNotARequestIsRefusedInsteadOfGuessed() {
        XCTAssertNil(HTTPRequestHead.parse(""))
        XCTAssertNil(HTTPRequestHead.parse("PROŚBA"))
    }
}

final class RequestRewriteTests: XCTestCase {
    private func rewrite(_ json: String, path: String) -> JSONValue? {
        JSONValue.parse(RequestRewrite.withUsageRequested(body: Data(json.utf8), path: path))
    }

    func testAStreamingV1RequestIsAskedForUsage() {
        let result = rewrite(#"{"model":"m","stream":true}"#, path: "/v1/chat/completions")
        XCTAssertEqual(result?["stream_options"]?["include_usage"], .bool(true))
        XCTAssertEqual(result?["model"]?.stringValue, "m")
    }

    func testAClientThatAlreadyAskedIsLeftAlone() {
        let body = #"{"model":"m","stream":true,"stream_options":{"include_usage":false}}"#
        let result = RequestRewrite.withUsageRequested(
            body: Data(body.utf8), path: "/v1/chat/completions"
        )
        XCTAssertEqual(String(decoding: result, as: UTF8.self), body)
    }

    func testOtherStreamOptionsSurvive() {
        let result = rewrite(
            #"{"stream":true,"stream_options":{"chunk_size":4}}"#, path: "/v1/completions"
        )
        XCTAssertEqual(result?["stream_options"]?["chunk_size"]?.intValue, 4)
        XCTAssertEqual(result?["stream_options"]?["include_usage"], .bool(true))
    }

    func testEverythingElsePassesThroughByteForByte() {
        // Pośrednik zmienia cudzy ruch w jednym jedynym miejscu; wszędzie
        // indziej ma być przezroczysty co do bajtu.
        let cases: [(String, String)] = [
            (#"{"model":"m","stream":true}"#, "/api/chat"),       // nie /v1
            (#"{"model":"m","stream":false}"#, "/v1/chat/completions"), // bez strumienia
            (#"{"model":"m"}"#, "/v1/chat/completions"),           // bez pola stream
            ("to nie jest JSON", "/v1/chat/completions"),
        ]
        for (body, path) in cases {
            let result = RequestRewrite.withUsageRequested(body: Data(body.utf8), path: path)
            XCTAssertEqual(String(decoding: result, as: UTF8.self), body, "ścieżka \(path)")
        }
    }
}

final class ResponseSummaryTests: XCTestCase {
    func testTheOllamaShapeIsReadFromTheLastLine() {
        let stream = """
        {"message":{"content":"a"},"done":false}
        {"message":{"content":"b"},"done":false}
        {"done":true,"prompt_eval_count":258,"eval_count":94}
        """
        let tokens = ResponseSummary.tokens(in: Data(stream.utf8))
        XCTAssertEqual(tokens?.prompt, 258)
        XCTAssertEqual(tokens?.generated, 94)
    }

    func testTheOpenAIShapeIsReadPastTheDoneMarker() {
        let stream = """
        data: {"choices":[{"delta":{"content":"a"}}]}

        data: {"choices":[],"usage":{"prompt_tokens":1200,"completion_tokens":40}}

        data: [DONE]

        """
        let tokens = ResponseSummary.tokens(in: Data(stream.utf8))
        XCTAssertEqual(tokens?.prompt, 1200)
        XCTAssertEqual(tokens?.generated, 40)
    }

    func testAPlainAnswerWithoutStreamingAlsoCarriesTheCounts() {
        let body = #"{"model":"m","done":true,"prompt_eval_count":17,"eval_count":3}"#
        XCTAssertEqual(ResponseSummary.tokens(in: Data(body.utf8))?.prompt, 17)
    }

    func testNoCountsMeansNilRatherThanZero() {
        // Zero byłoby tu kłamstwem tej samej rodziny co `truncated = 0`:
        // wyglądałoby na zmierzone, a jest brakiem pomiaru.
        XCTAssertNil(ResponseSummary.tokens(in: Data("data: [DONE]\n".utf8)))
        XCTAssertNil(ResponseSummary.tokens(in: Data()))
        XCTAssertNil(ResponseSummary.tokens(in: Data("Internal Server Error".utf8)))
    }
}
