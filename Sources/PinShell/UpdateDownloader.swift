import Foundation
import PinShellCore

/// 基于 URLSessionDownloadTask 的安装包下载器：带进度回调、可取消。
/// delegate queue 固定为主队列，所以进度/完成回调都在主线程。
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum DownloadError: LocalizedError {
        case httpStatus(Int)
        case incomplete(expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code):
                return String(format: NSLocalizedString("update.httpError", comment: ""), String(code))
            case .incomplete(let expected, let actual):
                return String(format: NSLocalizedString("update.sizeMismatch", comment: ""),
                              NumberFormat.bytes(expected),
                              NumberFormat.bytes(actual))
            }
        }
    }

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var expectedSize: Int64 = 0
    private var progressHandler: ((Int64, Int64) -> Void)?
    private var didComplete = false

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// 下载到 destination，返回文件位置。取消时抛出 CancellationError。
    func download(from url: URL,
                  expectedSize: Int64,
                  to destination: URL,
                  progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        try Task.checkCancellation()

        self.destination = destination
        self.expectedSize = expectedSize
        self.progressHandler = progress
        progress(0, expectedSize)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = self.session.downloadTask(with: url)
                self.task = task
                task.resume()
                // onCancel 可能先于任务创建执行；这里补一次取消检查
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        progressHandler?(totalBytesWritten, total)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { return }

        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(DownloadError.httpStatus(http.statusCode)))
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let actual = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if expectedSize > 0, actual != expectedSize {
                finish(.failure(DownloadError.incomplete(expected: expectedSize, actual: actual)))
                return
            }

            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 成功路径已在 didFinishDownloadingTo 收尾
        guard let error else { return }
        if (error as? URLError)?.code == .cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didComplete else { return }
        didComplete = true
        progressHandler = nil
        task = nil
        session.finishTasksAndInvalidate()

        let continuation = self.continuation
        self.continuation = nil
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}
