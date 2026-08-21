import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar web tools")
struct FamiliarWebTests {
    @Test("URL policy allows public HTTPS and rejects unsafe destinations")
    func urlPolicy() throws {
        let normalized = try FamiliarWebURLPolicy.normalize("HTTPS://Example.COM/path#fragment")
        #expect(normalized.absoluteString == "https://example.com/path")
        #expect(throws: FamiliarWebError.self) { try FamiliarWebURLPolicy.normalize("http://example.com") }
        #expect(throws: FamiliarWebError.self) { try FamiliarWebURLPolicy.normalize("https://user:pass@example.com") }
        #expect(throws: FamiliarWebError.self) { try FamiliarWebURLPolicy.normalize("https://localhost/private") }
        #expect(throws: FamiliarWebError.self) { try FamiliarWebURLPolicy.normalize("https://example.com:8443") }
    }

    @Test("IP policy blocks local, private, documentation and mapped addresses")
    func ipPolicy() {
        #expect(FamiliarWebURLPolicy.isPublicAddress("1.1.1.1"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("127.0.0.1"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("10.2.3.4"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("169.254.1.2"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("192.0.2.1"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("::1"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("fc00::1"))
        #expect(!FamiliarWebURLPolicy.isPublicAddress("::ffff:127.0.0.1"))
        #expect(FamiliarWebURLPolicy.isPublicAddress("2606:4700:4700::1111"))
    }

    @Test("DNS addresses preserve resolver order while removing duplicates")
    func dnsStableDeduplication() {
        let addresses = ["2001:db8::1", "1.1.1.1", "2001:db8::1", "8.8.8.8", "1.1.1.1"]
        #expect(FamiliarWebDNSResolver.stableUnique(addresses) == ["2001:db8::1", "1.1.1.1", "8.8.8.8"])
    }

    @Test("HTTP parser recognizes complete length and chunked bodies without socket close")
    func httpResponseCompleteness() throws {
        let partialLength = Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhell".utf8)
        let completeLength = Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello".utf8)
        #expect(try !FamiliarHTTPParser.isComplete(partialLength, bodyLimit: 100))
        #expect(try FamiliarHTTPParser.isComplete(completeLength, bodyLimit: 100))

        let partialChunked = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n".utf8)
        let completeChunked = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n\r\n".utf8)
        #expect(try !FamiliarHTTPParser.isComplete(partialChunked, bodyLimit: 100))
        #expect(try FamiliarHTTPParser.isComplete(completeChunked, bodyLimit: 100))
    }

    @Test("DuckDuckGo HTML parser unwraps and deduplicates result URLs")
    func duckDuckGoHTML() throws {
        let html = """
        <html><body><div class="results--main">
          <div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fstory&amp;rut=x">Example story</a><a class="result__snippet">A useful result.</a></div>
          <div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fstory&amp;rut=y">Duplicate</a></div>
          <div class="result"><a class="result__a" href="https://swift.org/blog/">Swift blog</a></div>
        </div></body></html>
        """
        let results = try FamiliarWebContentService.parseDuckDuckGoHTML(html, maximumResults: 5)
        #expect(results.count == 2)
        #expect(results[0].url == "https://example.com/story")
        #expect(results[0].snippet == "A useful result.")
        #expect(results[1].displayURL == "swift.org")
    }

    @Test("Readable HTML extractor removes navigation and scripts")
    func readableHTML() throws {
        let html = """
        <html><head><title>Article title</title><script>steal()</script></head><body>
          <nav>Navigation item</nav>
          <article><h1>Article title</h1><p>This is a sufficiently long paragraph containing the useful page content for the reader.</p><p>Second paragraph.</p></article>
          <footer>Footer</footer>
        </body></html>
        """
        let result = try FamiliarWebContentService.extractReadableHTML(html)
        #expect(result.title == "Article title")
        #expect(result.text.contains("useful page content"))
        #expect(!result.text.contains("Navigation item"))
        #expect(!result.text.contains("steal"))
    }

    @MainActor
    @Test("Sources persist with the assistant message without page content")
    func sourcePersistence() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let conversation = FamiliarConversation()
        let message = FamiliarMessage(role: .assistant, content: "Answer", sequence: 0, conversation: conversation)
        let source = FamiliarSourceRecord(
            sourceID: "src_123",
            kind: .fetchedPage,
            title: "Example",
            urlString: "https://example.com/",
            siteName: "example.com",
            snippet: "Evidence excerpt",
            sequence: 0,
            retrievedAt: Date(),
            message: message
        )
        context.insert(conversation)
        context.insert(message)
        context.insert(source)
        try context.save()

        let records = try context.fetch(FetchDescriptor<FamiliarSourceRecord>())
        #expect(records.count == 1)
        #expect(records[0].urlString == "https://example.com/")
        #expect(records[0].snippet == "Evidence excerpt")
        #expect(records[0].message?.content == "Answer")
    }
}
