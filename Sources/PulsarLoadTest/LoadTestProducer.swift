import Foundation
import PulsarClient
import Logging

/// Manages message production for load testing
public actor LoadTestProducer {
    private let configuration: LoadTestConfiguration
    private let client: PulsarClient
    private let logger: Logger
    private var producer: (any ProducerProtocol<String>)?

    // State tracking
    private var isRunning = false
    private var task: Task<Void, Error>?
    private var messageCount = 0
    private var startTime: Date?

    public init(
        configuration: LoadTestConfiguration,
        client: PulsarClient,
        logger: Logger
    ) {
        self.configuration = configuration
        self.client = client
        self.logger = logger
    }

    public func start() async throws {
        guard !isRunning else {
            logger.warning("Producer already running")
            return
        }

        logger.info("Starting producer", metadata: [
            "topic": "\(configuration.topic)",
            "rate": "\(configuration.messageRate.description)",
            "duration": "\(configuration.duration)s"
        ])

        // Create producer
        let deviceId = configuration.deviceId
        self.producer = try await client.newProducer(
            topic: configuration.topic,
            schema: Schema<String>.string
        ) { builder in
            builder
                .producerName("\(deviceId)-producer")
                .batchingEnabled(true)
                .batchingMaxMessages(100)
                .batchingMaxDelay(0.01)
                .sendTimeout(30)
        }

        isRunning = true
        startTime = Date()
        messageCount = 0

        // Start production task
        task = Task { [weak self] in
            try await self?.runProduction()
    }

    public func stop() async {
        guard isRunning else { return }

        logger.info("Stopping producer", metadata: [
            "messagesSent": "\(messageCount)"
        ])

        isRunning = false
        task?.cancel()
        await producer?.dispose()
        producer = nil
    }

    private func runProduction() async throws {
        let messageDelay = configuration.messageRate.messageDelay
        let messageSize = configuration.messageSize
        let endTime = Date().addingTimeInterval(configuration.duration)

        logger.info("Starting message production", metadata: [
            "messageDelay": "\(messageDelay)s",
            "messageSize": "\(messageSize) bytes",
            "totalMessages": "\(configuration.totalMessages)"
        ])

        while isRunning && Date() < endTime {
            try Task.checkCancellation()

            // Generate message payload
            let timestamp = Date().timeIntervalSince1970
            let message = generateMessage(
                size: messageSize,
                sequence: messageCount,
                timestamp: timestamp
            )

            // Send message
            do {
                let messageId = try await producer?.send(message)
                messageCount += 1

                if messageCount % 1000 == 0 {
                    let actualRate = calculateActualRate()
                    logger.info("Production progress", metadata: [
                        "messagesSent": "\(messageCount)",
                        "actualRate": "\(String(format: "%.2f", actualRate)) msg/s",
                        "lastMessageId": "\(messageId?.description ?? "unknown")"
                    ])
                }
            } catch {
                logger.error("Failed to send message", metadata: [
                    "error": "\(error)",
                    "sequence": "\(messageCount)"
                ])
            }

            // Rate limiting
            if messageDelay > 0 {
                try await Task.sleep(for: .seconds(messageDelay))
            }
        }

        let actualRate = calculateActualRate()
        logger.info("Production completed", metadata: [
            "totalSent": "\(messageCount)",
            "duration": "\(Date().timeIntervalSince(startTime ?? Date()))s",
            "averageRate": "\(String(format: "%.2f", actualRate)) msg/s"
        ])
    }

    private func generateMessage(size: Int, sequence: Int, timestamp: TimeInterval) -> String {
        // Create structured message with padding to reach desired size
        let header = """
        {
          "device_id": "\(configuration.deviceId)",
          "sequence": \(sequence),
          "timestamp": \(timestamp),
          "test_run": "\(startTime?.timeIntervalSince1970 ?? 0)",
          "data": "
        """

        let footer = "\"}"
        let headerSize = header.utf8.count + footer.utf8.count
        let paddingSize = max(0, size - headerSize)

        // Generate padding data
        let padding = String(repeating: "x", count: paddingSize)

        return header + padding + footer
    }

    private func calculateActualRate() -> Double {
        guard let startTime = startTime else { return 0 }
        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return Double(messageCount) / duration
    }

    public func getStatistics() async -> ProducerStatistics {
        ProducerStatistics(
            messagesSent: messageCount,
            actualRate: calculateActualRate(),
            isRunning: isRunning
        )
    }
}

public struct ProducerStatistics: Sendable {
    public let messagesSent: Int
    public let actualRate: Double
    public let isRunning: Bool
}