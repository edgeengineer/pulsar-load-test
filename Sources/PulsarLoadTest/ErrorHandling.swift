import Foundation
import Logging

/// Custom error types for load testing
public enum LoadTestError: LocalizedError {
    case configurationError(String)
    case connectionFailed(String)
    case producerError(String)
    case consumerError(String)
    case metricsError(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration Error: \(message)"
        case .connectionFailed(let message):
            return "Connection Failed: \(message)"
        case .producerError(let message):
            return "Producer Error: \(message)"
        case .consumerError(let message):
            return "Consumer Error: \(message)"
        case .metricsError(let message):
            return "Metrics Error: \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        }
    }
}

/// Retry policy for operations
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let exponentialBackoff: Bool

    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        exponentialBackoff: true
    )

    public func delay(for attempt: Int) -> TimeInterval {
        guard exponentialBackoff else { return baseDelay }

        let delay = baseDelay * pow(2.0, Double(attempt - 1))
        return min(delay, maxDelay)
    }
}

/// Retry helper with exponential backoff
public func withRetry<T>(
    policy: RetryPolicy = .default,
    logger: Logger? = nil,
    operation: String,
    body: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1...policy.maxAttempts {
        do {
            return try await body()
        } catch {
            lastError = error

            logger?.warning("Operation failed, attempt \(attempt)/\(policy.maxAttempts)", metadata: [
                "operation": "\(operation)",
                "error": "\(error)",
                "attempt": "\(attempt)"
            ])

            if attempt < policy.maxAttempts {
                let delay = policy.delay(for: attempt)
                logger?.debug("Retrying after \(delay) seconds")
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    throw lastError ?? LoadTestError.timeout("Operation '\(operation)' failed after \(policy.maxAttempts) attempts")
}

/// Error recovery strategies
public enum RecoveryStrategy {
    case retry(RetryPolicy)
    case skip
    case fail
    case reconnect
}

/// Health check result
public struct HealthStatus {
    public let component: String
    public let isHealthy: Bool
    public let message: String?
    public let lastCheckTime: Date

    public var metadata: Logger.Metadata {
        var meta: Logger.Metadata = [
            "component": "\(component)",
            "healthy": "\(isHealthy)",
            "lastCheck": "\(lastCheckTime)"
        ]
        if let message = message {
            meta["message"] = "\(message)"
        }
        return meta
    }
}

/// Health monitor for components
public actor HealthMonitor {
    private var statuses: [String: HealthStatus] = [:]
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    public func updateStatus(
        component: String,
        isHealthy: Bool,
        message: String? = nil
    ) {
        let status = HealthStatus(
            component: component,
            isHealthy: isHealthy,
            message: message,
            lastCheckTime: Date()
        )

        statuses[component] = status

        if !isHealthy {
            logger.warning("Component unhealthy", metadata: status.metadata)
        }
    }

    public func isSystemHealthy() -> Bool {
        statuses.values.allSatisfy { $0.isHealthy }
    }

    public func getStatuses() -> [HealthStatus] {
        Array(statuses.values)
    }

    public func logHealthSummary() {
        let healthy = statuses.values.filter { $0.isHealthy }.count
        let total = statuses.count

        logger.info("Health summary", metadata: [
            "healthy": "\(healthy)",
            "total": "\(total)",
            "systemHealthy": "\(isSystemHealthy())"
        ])

        for status in statuses.values {
            if !status.isHealthy {
                logger.warning("Unhealthy component", metadata: status.metadata)
            }
        }
    }
}