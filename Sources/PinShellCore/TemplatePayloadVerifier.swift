import Foundation

public enum TemplatePayloadVerificationError: Error, Equatable, CustomStringConvertible {
    case tooLarge(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case checksumMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .tooLarge(let bytes):
            return "payload exceeds \(TemplateLibraryValidation.maxPayloadBytes) bytes (got \(bytes))"
        case .sizeMismatch(let expected, let actual):
            return "payload size mismatch: expected \(expected), got \(actual)"
        case .checksumMismatch(let expected, let actual):
            return "payload checksum mismatch: expected \(expected), got \(actual)"
        }
    }
}

public enum TemplatePayloadVerifier {
    public static func verify(data: Data,
                              expectedBytes: Int,
                              expectedSHA256: String) throws {
        guard data.count <= TemplateLibraryValidation.maxPayloadBytes else {
            throw TemplatePayloadVerificationError.tooLarge(data.count)
        }
        guard data.count == expectedBytes else {
            throw TemplatePayloadVerificationError.sizeMismatch(
                expected: expectedBytes, actual: data.count)
        }
        let actual = FileDigest.sha256(of: data)
        guard actual == expectedSHA256.lowercased() else {
            throw TemplatePayloadVerificationError.checksumMismatch(
                expected: expectedSHA256, actual: actual)
        }
    }
}
