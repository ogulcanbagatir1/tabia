import Foundation
import Compression

/// Streaming gzip → file decompressor built on Apple's `Compression` framework (raw DEFLATE),
/// so the hosted reference database can ship as `.pgn.gz` and be decompressed with ZERO external
/// dependencies (Tabia bundles none). Input is memory-mapped and output is streamed to disk, so
/// peak memory stays flat regardless of file size.
enum GzipDecompressor {

    enum GzipError: Error { case notGzip, unsupportedMethod, streamInit, streamFailed }

    /// Decompress a gzip file to `dst` (overwriting it). Memory-bounded.
    static func decompress(src: URL, to dst: URL) throws {
        let input = try Data(contentsOf: src, options: .mappedIfSafe)
        guard input.count > 18, input[input.startIndex] == 0x1f, input[input.startIndex + 1] == 0x8b else {
            throw GzipError.notGzip
        }
        guard input[input.startIndex + 2] == 0x08 else { throw GzipError.unsupportedMethod }  // DEFLATE

        // Parse the gzip header to find where the raw DEFLATE stream begins.
        let flg = input[input.startIndex + 3]
        var idx = 10
        if flg & 0x04 != 0 {                                   // FEXTRA
            let xlen = Int(input[input.startIndex + idx]) | (Int(input[input.startIndex + idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flg & 0x08 != 0 {                                   // FNAME (null-terminated)
            while idx < input.count && input[input.startIndex + idx] != 0 { idx += 1 }
            idx += 1
        }
        if flg & 0x10 != 0 {                                   // FCOMMENT (null-terminated)
            while idx < input.count && input[input.startIndex + idx] != 0 { idx += 1 }
            idx += 1
        }
        if flg & 0x02 != 0 { idx += 2 }                        // FHCRC
        guard idx < input.count else { throw GzipError.notGzip }

        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let out = try FileHandle(forWritingTo: dst)
        defer { try? out.close() }

        let bufSize = 1 << 20
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { dstBuf.deallocate() }

        // Init with dstBuf as placeholder pointers; compression_stream_init overwrites them.
        var stream = compression_stream(dst_ptr: dstBuf, dst_size: 0,
                                        src_ptr: UnsafePointer(dstBuf), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GzipError.streamInit
        }
        defer { compression_stream_destroy(&stream) }

        var thrown: Error?
        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            stream.src_ptr = base + idx
            stream.src_size = input.count - idx
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                stream.dst_ptr = dstBuf
                stream.dst_size = bufSize
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufSize - stream.dst_size
                    if produced > 0 { out.write(Data(bytes: dstBuf, count: produced)) }
                    if status == COMPRESSION_STATUS_END { return }
                default:
                    thrown = GzipError.streamFailed
                    return
                }
            }
        }
        if let thrown { throw thrown }
    }
}
