import Compression
import Foundation

/// Decodes HTTP `Content-Encoding` for the restricted fetch client. Some CDNs
/// send gzip even when identity is requested, so gzip and deflate are accepted.
/// Output is bounded to defend against decompression bombs.
nonisolated enum FamiliarHTTPContentDecoding {
    static func isSupported(_ contentEncoding: String?) -> Bool {
        switch normalized(contentEncoding) {
        case nil, "identity", "gzip", "x-gzip", "deflate": true
        default: false
        }
    }

    static func decode(_ body: Data, contentEncoding: String?, limit: Int) throws -> Data {
        guard !body.isEmpty else { return body }
        switch normalized(contentEncoding) {
        case nil, "identity": return body
        case "gzip", "x-gzip": return try inflate(stripGzipFraming(body), limit: limit)
        case "deflate": return try inflate(stripZlibHeader(body), limit: limit)
        default: throw FamiliarWebError.unsupportedContentEncoding
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        return value
    }

    /// RFC 1952: 10-byte header, optional FEXTRA/FNAME/FCOMMENT/FHCRC, 8-byte trailer.
    private static func stripGzipFraming(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw FamiliarWebError.malformedResponse
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { throw FamiliarWebError.malformedResponse }
            index += 2 + Int(bytes[index]) | Int(bytes[index + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }
        guard index < bytes.count - 8 else { throw FamiliarWebError.malformedResponse }
        return Data(bytes[index..<(bytes.count - 8)])
    }

    /// HTTP "deflate" is usually zlib-wrapped; some servers send raw deflate.
    private static func stripZlibHeader(_ data: Data) -> Data {
        let bytes = [UInt8](data.prefix(2))
        guard bytes.count == 2, bytes[0] & 0x0F == 8,
              (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) % 31 == 0 else { return data }
        return data.dropFirst(2)
    }

    private static func inflate(_ input: Data, limit: Int) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw FamiliarWebError.malformedResponse
        }
        defer { compression_stream_destroy(stream) }
        let bufferSize = 64 * 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var output = Data()
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { throw FamiliarWebError.malformedResponse }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count
            var status: compression_status
            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR else { throw FamiliarWebError.malformedResponse }
                let produced = bufferSize - stream.pointee.dst_size
                output.append(buffer, count: produced)
                guard output.count <= limit else { throw FamiliarWebError.responseTooLarge }
                // No progress with no input left means a truncated stream.
                if status == COMPRESSION_STATUS_OK, produced == 0, stream.pointee.src_size == 0 {
                    throw FamiliarWebError.malformedResponse
                }
            } while status == COMPRESSION_STATUS_OK
        }
        return output
    }
}
