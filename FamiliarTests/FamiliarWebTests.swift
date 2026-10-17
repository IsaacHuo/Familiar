import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar web tools")
struct FamiliarWebTests {
    @Test("HTTP request targets preserve trailing slash and reserved escapes without header injection")
    func requestTargetEncoding() throws {
        let url = try FamiliarWebURLPolicy.normalize("https://example.com/a%2Fb/?q=x%2Fy")
        let request = FamiliarRestrictedHTTPClient.makeRequest(url: url, host: "example.com", method: "GET", body: nil)
        let text = String(decoding: request, as: UTF8.self)
        #expect(text.hasPrefix("GET /a%2Fb/?q=x%2Fy HTTP/1.1\r\n"))
        let injected = try FamiliarWebURLPolicy.normalize("https://example.com/a%0D%0AX-Injected:%20yes/")
        let safe = String(decoding: FamiliarRestrictedHTTPClient.makeRequest(url: injected, host: "example.com", method: "GET", body: nil), as: UTF8.self)
        #expect(safe.contains("%0D%0A"))
        #expect(!safe.contains("\r\nX-Injected:"))
    }
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
        // Proxy fake-IP range is reachable public traffic, not a LAN.
        #expect(FamiliarWebURLPolicy.isPublicAddress("198.18.0.5"))
    }

    @Test("gzip and deflate bodies decode within the output bound")
    func contentEncoding() throws {
        let payload = Data(String(repeating: "hello web page ", count: 200).utf8)
        let deflated = try (payload as NSData).compressed(using: .zlib) as Data
        let gzip = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03]) + deflated + Data(count: 8)
        #expect(try FamiliarHTTPContentDecoding.decode(gzip, contentEncoding: "gzip", limit: 1_000_000) == payload)
        #expect(try FamiliarHTTPContentDecoding.decode(deflated, contentEncoding: "deflate", limit: 1_000_000) == payload)
        #expect(throws: FamiliarWebError.self) { try FamiliarHTTPContentDecoding.decode(gzip, contentEncoding: "gzip", limit: 100) }
        #expect(throws: FamiliarWebError.self) { try FamiliarHTTPContentDecoding.decode(gzip, contentEncoding: "br", limit: 1_000_000) }
        let response = Data("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: \(gzip.count)\r\n\r\n".utf8) + gzip
        #expect(try FamiliarHTTPParser.isComplete(response, bodyLimit: 1_000_000))
    }

    @Test("Chinese pages declared by meta charset decode without mojibake")
    func metaCharset() throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let body = try #require("<p>中文网页正文内容</p>".data(using: gb))
        let html = Data("<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=gbk\"></head><body>".utf8) + body
        let text = try #require(FamiliarWebContentService.decodeText(html, contentType: "text/html"))
        #expect(text.contains("中文网页正文内容"))
        let header = try #require(FamiliarWebContentService.decodeText(body, contentType: "text/html; charset=GB2312"))
        #expect(header.contains("中文网页"))
    }

    @Test("Extraction keeps content inside page-wide forms and flagged containers")
    func extractionKeepsWrappedContent() throws {
        let html = """
        <html><body class="comments-enabled"><form id="aspnetForm"><div class="has-social-share">
        <article><h1>Wrapped</h1><p>This paragraph is the real article content and must survive extraction intact.</p></article>
        </div><input type="hidden" value="state"></form></body></html>
        """
        let result = try FamiliarWebContentService.extractReadableHTML(html)
        #expect(result.text.contains("real article content"))
        #expect(!result.text.contains("state"))
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

    @Test("Bing HTML parser ignores internal links and keeps direct sources")
    func bingHTML() throws {
        let html = """
        <html><body><ol>
          <li class="b_algo"><div class="b_algoheader"><a href="https://example.com/beijing"><h2>Beijing</h2></a></div><div class="b_caption"><p>City guide.</p></div></li>
          <li class="b_algo"><h2><a href="https://www.bing.com/internal">Internal</a></h2></li>
        </ol></body></html>
        """
        let results = try FamiliarWebContentService.parseBingHTML(html, maximumResults: 5)
        #expect(results.count == 1)
        #expect(results.first?.title == "Beijing")
        #expect(results.first?.snippet == "City guide.")
    }

    @Test("Bing production redirect links decode to public source URLs")
    func bingRedirectLinks() throws {
        let destination = "https://developer.apple.com/swift/?utm_source=bing"
        let encoded = "a1" + Data(destination.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let html = "<li class='b_algo'><h2><a href='https://www.bing.com/ck/a?u=" + encoded + "'>Swift</a></h2></li>"
        let results = try FamiliarWebContentService.parseBingHTML(html, maximumResults: 5)
        #expect(results.first?.url == "https://developer.apple.com/swift/")
        let privateURL = "a1" + Data("https://localhost/private".utf8).base64EncodedString()
        let unsafe = "<li class='b_algo'><h2><a href='https://www.bing.com/ck/a?u=" + privateURL + "'>Private</a></h2></li>"
        #expect(throws: FamiliarWebError.self) { try FamiliarWebContentService.parseBingHTML(unsafe, maximumResults: 5) }
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
