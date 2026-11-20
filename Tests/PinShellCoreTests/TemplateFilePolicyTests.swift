import XCTest
@testable import PinShellCore

final class TemplateFilePolicyTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/PinShellTemplates", isDirectory: true)

    func testResolvesPlainFileName() throws {
        let url = try TemplateFilePolicy.resolve(name: "todo.html", in: directory)
        XCTAssertEqual(url.path, "/tmp/PinShellTemplates/todo.html")
        XCTAssertEqual(try TemplateFilePolicy.resolve(name: "SOCIAL.HTM", in: directory).lastPathComponent,
                       "SOCIAL.HTM")
    }

    func testTrimsWhitespace() throws {
        let url = try TemplateFilePolicy.resolve(name: "  todo.html\n", in: directory)
        XCTAssertEqual(url.lastPathComponent, "todo.html")
    }

    func testRejectsTraversalAndSubdirectories() {
        for name in ["", "   ", ".", "..", "../evil.html", "sub/x.html", "/etc/passwd.html", "a\\b.html"] {
            XCTAssertThrowsError(try TemplateFilePolicy.resolve(name: name, in: directory), name)
        }
    }

    func testRejectsUnsupportedExtensions() {
        for name in ["todo", "todo.txt", ".html", "todo.html.js"] {
            XCTAssertThrowsError(try TemplateFilePolicy.resolve(name: name, in: directory), name)
        }
    }

    func testEnsureInsideRejectsSymlinkEscape() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("PinShellPolicy-\(UUID().uuidString)",
                                                                isDirectory: true)
        let outside = fm.temporaryDirectory.appendingPathComponent("PinShellOutside-\(UUID().uuidString).html")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html></html>".write(to: outside, atomically: true, encoding: .utf8)
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: outside)
        }

        let link = root.appendingPathComponent("linked.html")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try TemplateFilePolicy.ensureInside(link, directory: root))

        let inside = root.appendingPathComponent("ok.html")
        try "<html></html>".write(to: inside, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try TemplateFilePolicy.ensureInside(inside, directory: root))
    }
}
