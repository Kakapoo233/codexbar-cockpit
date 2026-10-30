import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession's data delegate bounds memory as chunks arrive, including platforms without AsyncBytes.
/// The lock guards the continuation, buffer, task and cancellation race between callback queues.
final class CockpitTeamHTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
        var task: URLSessionDataTask?
        var response: URLResponse?
        var data = Data()
        var failure: (any Error)?
        var cancelled = false
    }

    private let lock = NSLock()
    private var state = State()

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil
                config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil
                config.urlCache = nil
                config.timeoutIntervalForRequest = 30
                config.timeoutIntervalForResource = 45
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                let cancelled = self.lock.withLock {
                    self.state.continuation = continuation
                    self.state.task = task
                    return self.state.cancelled
                }
                if cancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            let task = self.lock.withLock {
                self.state.cancelled = true
                return self.state.task
            }
            task?.cancel()
        }
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    {
        let accepted = self.lock.withLock {
            guard response.expectedContentLength <= CockpitTeamClient.maximumResponseBytes else {
                self.state.failure = CockpitTeamError.responseTooLarge
                return false
            }
            self.state.response = response
            return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let oversized = self.lock.withLock {
            guard self.state.data.count <= CockpitTeamClient.maximumResponseBytes - data.count else {
                self.state.failure = CockpitTeamError.responseTooLarge
                return true
            }
            self.state.data.append(data)
            return false
        }
        if oversized { dataTask.cancel() }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    {
        completionHandler(nil)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?)
            -> Void)
    {
        // Let the OS validate TLS trust. Never offer credentials to an HTTP authentication challenge.
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        #endif
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let completed = self.lock.withLock { () -> (
            CheckedContinuation<(Data, URLResponse), any Error>?,
            Result<(Data, URLResponse), any Error>) in
            let result: Result<(Data, URLResponse), any Error> = if self.state.cancelled {
                .failure(CancellationError())
            } else if let failure = self.state.failure ?? error {
                .failure(failure)
            } else if let response = self.state.response {
                .success((self.state.data, response))
            } else {
                .failure(CockpitTeamError.invalidResponse)
            }
            let continuation = self.state.continuation
            self.state.continuation = nil
            self.state.task = nil
            self.state.data = Data()
            return (continuation, result)
        }
        session.finishTasksAndInvalidate()
        completed.0?.resume(with: completed.1)
    }
}
