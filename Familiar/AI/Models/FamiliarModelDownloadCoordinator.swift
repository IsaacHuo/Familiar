import Foundation

/// Resumable download primitive shared by local model managers.
nonisolated final class FamiliarModelDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progressHandler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var completedURL: URL?
    private var pausing = false

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        progressHandler = progress
    }

    var hasResumeData: Bool { lock.withLock { resumeData != nil } }

    func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    completedURL = nil
                    pausing = false
                    let configuration = URLSessionConfiguration.default
                    configuration.allowsCellularAccess = true
                    let session = URLSession(
                        configuration: configuration,
                        delegate: self,
                        delegateQueue: nil
                    )
                    self.session = session
                    let task = resumeData.map(session.downloadTask(withResumeData:))
                        ?? session.downloadTask(with: url)
                    self.task = task
                    task.resume()
                }
            }
        }, onCancel: { self.cancel() })
    }

    func pause() {
        lock.withLock { pausing = true }
        task?.cancel { data in
            self.lock.withLock { self.resumeData = data }
        }
    }

    func cancel() {
        lock.withLock {
            pausing = false
            resumeData = nil
        }
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            lock.withLock {
                completedURL = destination
                resumeData = nil
            }
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            let nsError = error as NSError
            if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                lock.withLock { resumeData = data }
            }
            finish(.failure(lock.withLock { pausing } ? CancellationError() : error))
        } else if let url = lock.withLock({ completedURL }) {
            finish(.success(url))
        }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer {
                self.continuation = nil
                task = nil
                session = nil
            }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
