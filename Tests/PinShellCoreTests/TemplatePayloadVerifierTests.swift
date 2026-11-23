import XCTest
@testable import PinShellCore

final class TemplatePayloadVerifierTests: XCTestCase {
    private let abcData = Data("abc".utf8)
    private let abcSHA = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    func testSHA256KnownVector() {
        XCTAssertEqual(FileDigest.sha256(of: abcData), abcSHA)
    }

    func testVerifierAcceptsExactPayload() throws {
        XCTAssertNoThrow(try TemplatePayloadVerifier.verify(
            data: abcData, expectedBytes: 3, expectedSHA256: abcSHA))
        XCTAssertNoThrow(try TemplatePayloadVerifier.verify(
            data: abcData, expectedBytes: 3, expectedSHA256: abcSHA.uppercased()))
    }

    func testVerifierRejectsSizeMismatch() {
        XCTAssertThrowsError(try TemplatePayloadVerifier.verify(
            data: abcData, expectedBytes: 4, expectedSHA256: abcSHA)) {
            XCTAssertEqual($0 as? TemplatePayloadVerificationError,
                           .sizeMismatch(expected: 4, actual: 3))
        }
    }

    func testVerifierRejectsChecksumMismatch() {
        let wrong = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try TemplatePayloadVerifier.verify(
            data: abcData, expectedBytes: 3, expectedSHA256: wrong)) {
            guard case .some(.checksumMismatch) = $0 as? TemplatePayloadVerificationError else {
                return XCTFail("expected checksum mismatch")
            }
        }
    }

    func testVerifierRejectsOversizedPayload() {
        let data = Data(repeating: 0x61,
                        count: TemplateLibraryValidation.maxPayloadBytes + 1)
        XCTAssertThrowsError(try TemplatePayloadVerifier.verify(
            data: data, expectedBytes: data.count, expectedSHA256: abcSHA)) {
            guard case .some(.tooLarge) = $0 as? TemplatePayloadVerificationError else {
                return XCTFail("expected tooLarge")
            }
        }
    }
}
