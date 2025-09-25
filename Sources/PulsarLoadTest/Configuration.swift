import Foundation
import Logging

/// Represents the operational mode of the load test
public enum RunMode: String, CaseIterable, CustomStringConvertible, Sendable {
    case consumer = "consumer"
    case producer = "producer"
    case both = "both"

    public var description: String {
        switch self {
        case .consumer: return "Consumer Only"
        case .producer: return "Producer Only"
        case .both: return "Producer and Consumer"
        }
    }
}

/// Configuration for message production rate
public struct MessageRate: CustomStringConvertible, Sendable {
    public let messagesPerInterval: Int
    public let interval: TimeInterval

    /// Messages per second calculated from the configured rate
    public var messagesPerSecond: Double {
        Double(messagesPerInterval) / interval
    }

    /// Delay between messages in seconds
    public var messageDelay: TimeInterval {
        guard messagesPerInterval > 0 else { return 0 }
        return interval / Double(messagesPerInterval)
    }

    public var description: String {
        if interval == 60 {
            return "\(messagesPerInterval) messages/minute"
        } else if interval == 3600 {
            return "\(messagesPerInterval) messages/hour"
        } else if interval == 1 {
            return "\(messagesPerInterval) messages/second"
        } else {
            return "\(messagesPerInterval) messages per \(interval) seconds"
        }
    }

    /// Parse a rate string like "10/minute" or "60/second"
    public static func parse(_ rateString: String) throws -> MessageRate {
        let components = rateString.split(separator: "/")
        guard components.count == 2,
              let count = Int(components[0]) else {
            throw ConfigurationError.invalidMessageRate(rateString)
        }

        let unit = String(components[1]).lowercased()
        let interval: TimeInterval

        switch unit {
        case "second", "seconds", "s":
            interval = 1
        case "minute", "minutes", "min", "m":
            interval = 60
        case "hour", "hours", "h":
            interval = 3600
        default:
            throw ConfigurationError.invalidMessageRate(rateString)
        }

        return MessageRate(messagesPerInterval: count, interval: interval)
    }
}

/// Load test configuration
public struct LoadTestConfiguration: Sendable {
    public let mode: RunMode
    public let messageRate: MessageRate
    public let duration: TimeInterval
    public let topic: String
    public let subscription: String
    public let serviceUrl: String
    public let prometheusPort: Int
    public let deviceId: String
    public let messageSize: Int

    /// Total number of messages to send during the test
    public var totalMessages: Int {
        Int(duration * messageRate.messagesPerSecond)
    }

    public init(
        mode: RunMode,
        messageRate: MessageRate,
        duration: TimeInterval,
        topic: String,
        subscription: String,
        serviceUrl: String,
        prometheusPort: Int,
        deviceId: String? = nil,
        messageSize: Int = 1024
    ) {
        self.mode = mode
        self.messageRate = messageRate
        self.duration = duration
        self.topic = topic
        self.subscription = subscription
        self.serviceUrl = serviceUrl
        self.prometheusPort = prometheusPort
        self.deviceId = deviceId ?? Self.generateDeviceId()
        self.messageSize = messageSize
    }

    private static func generateDeviceId() -> String {
        let hostname = ProcessInfo.processInfo.hostName
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(hostname)-\(timestamp)"
    }

    public func logConfiguration(to logger: Logger) {
        logger.info("Load Test Configuration", metadata: [
            "mode": "\(mode.description)",
            "messageRate": "\(messageRate.description)",
            "duration": "\(formatDuration(duration))",
            "totalMessages": "\(totalMessages)",
            "topic": "\(topic)",
            "subscription": "\(subscription)",
            "serviceUrl": "\(serviceUrl)",
            "prometheusPort": "\(prometheusPort)",
            "deviceId": "\(deviceId)",
            "messageSize": "\(messageSize) bytes"
        ])
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days) days, \(remainingHours) hours"
        } else if hours > 0 {
            return "\(hours) hours, \(minutes) minutes"
        } else if minutes > 0 {
            return "\(minutes) minutes, \(seconds) seconds"
        } else {
            return "\(seconds) seconds"
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case invalidMessageRate(String)
    case invalidDuration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMessageRate(let rate):
            return "Invalid message rate format: '\(rate)'. Use format like '10/minute' or '60/second'"
        case .invalidDuration(let duration):
            return "Invalid duration format: '\(duration)'. Use format like '48h', '1w', or '3600s'"
        }
    }
}