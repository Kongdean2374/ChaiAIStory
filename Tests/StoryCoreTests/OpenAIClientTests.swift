import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StoryCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let mutex = NSLock()
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.mutex.lock(); let handler = Self.handler; Self.mutex.unlock()
            let (status, data) = try XCTUnwrap(handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class OpenAIClientTests: XCTestCase {
    func client(handler: @escaping (URLRequest) throws -> (Int, Data)) -> OpenAIClient {
        MockURLProtocol.mutex.lock(); MockURLProtocol.handler = handler; MockURLProtocol.mutex.unlock()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return OpenAIClient(key: "test-placeholder", transport: URLSession(configuration: config))
    }
    func testUnauthorizedForbiddenRateLimit() async throws {
        for code in [401,403,429] {
            let api = client { _ in (code, Data("{\"error\":{\"message\":\"test-placeholder\"}}".utf8)) }
            do { _ = try await api.models(); XCTFail("Should fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains(String(code))); XCTAssertFalse(error.localizedDescription.contains("test-placeholder")) }
        }
    }
    func testNoKeyBeforeNetwork() async {
        do { _ = try await OpenAIClient(key: "").models(); XCTFail("Missing key") }
        catch { XCTAssertTrue(error.localizedDescription.contains("API Key")) }
    }
    func testModelList() async throws {
        let api = client { _ in (200, Data("{\"data\":[{\"id\":\"model-b\"},{\"id\":\"model-a\"}]}".utf8)) }
        let models = try await api.models()
        XCTAssertEqual(models, ["model-a","model-b"])
    }
    func testResponsesRequestAndSameIDRetrieval() async throws {
        let api = client { request in
            XCTAssertEqual(request.url?.host, "api.openai.com")
            if request.httpMethod == "GET" { XCTAssertTrue(request.url!.path.hasSuffix("resp_original")) }
            return (200, Data("{\"id\":\"resp_original\",\"status\":\"queued\",\"output\":[]}".utf8))
        }
        let response = try await api.create(model: "test", input: [["role":"user","content":"test"]], background: true)
        let polled = try await api.retrieve(response.id)
        XCTAssertEqual(polled.id, "resp_original")
    }
    func testOfflineErrorNoAutomaticRetry() async {
        var calls = 0
        let api = client { _ in calls += 1; throw URLError(.notConnectedToInternet) }
        do { _ = try await api.create(model: "test", input: [], background: true); XCTFail("offline") } catch {}
        XCTAssertEqual(calls, 1)
    }
}
