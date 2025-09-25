import Foundation
import PulsarClient
import Logging

/// Manages message consumption for load testing
public actor LoadTestConsumer {
    private let configuration: LoadTestConfiguration
    private let client: PulsarClient
    private let logger: Logger
    private var consumer: (any ConsumerProtocol<String>)?

    // State tracking
    private var isRunning = false
    private var task: Task<Void, Error>?
    private var messageCount = 0
    private var startTime: Date?
    private var lastMessageTime: Date?

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
            logger.warning("Consumer already running")
            return
        }

        logger.info("Starting consumer", metadata: [
            "topic": "\(configuration.topic)",
            "subscription": "\(configuration.subscription)",
            "duration": "\(configuration.duration)s"
        ])

        // Create consumer - PulsarClient will automatically emit metrics
        let deviceId = configuration.deviceId
        let subscription = configuration.subscription
        self.consumer = try await client.newConsumer(
            topic: configuration.topic,
            schema: Schema<String>.string
        ) { builder in
            builder
                .subscriptionName(subscription)
                .subscriptionType(.shared)
                .consumerName("\(deviceId)-consumer")
        }

        isRunning = true
        startTime = Date()
        messageCount = 0

        // Start consumption task
        task = Task { [weak self] in
            try await self?.runConsumption()
        }
    }

    public func stop() async {
        guard isRunning else { return }

        logger.info("Stopping consumer", metadata: [
            "messagesReceived": "\(messageCount)"
        ])

        isRunning = false
        task?.cancel()

        // Close consumer gracefully
        if let consumer = consumer {
            await consumer.dispose()
        }
        consumer = nil
    }

    private func runConsumption() async throws {
        let endTime = Date().addingTimeInterval(configuration.duration)

        logger.info("Starting message consumption", metadata: [
            "endTime": "\(endTime)"
        ])

        guard let consumer = consumer else { return }

        // Use async iteration for consuming messages
        while isRunning && Date() < endTime {
            try Task.checkCancellation()

            do {
                // Create a timeout task
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(1))
                    return nil as Message<String>?
                }

                // Create a receive task
                let receiveTask = Task { () -> Message<String>? in
                    // Get the next message from the async sequence
                    do {
                        for try await message in consumer {
                            if let msg = message as? Message<String> {
                                return msg
                            }
                        }
                    } catch {
                        return nil
                    }
                    return nil
                }

                // Race between timeout and receive
                let message: Message<String>? = await withTaskCancellationHandler {
                    let result = await receiveTask.value
                    timeoutTask.cancel()
                    return result
                } onCancel: {
                    receiveTask.cancel()
                    timeoutTask.cancel()
                }

                if let message = message {
                    lastMessageTime = Date()

                    // Process message
                    processMessage(message)

                    // Calculate end-to-end latency if message contains timestamp
                    if let messageData = parseMessage(message.value),
                       let timestamp = messageData["timestamp"] as? TimeInterval {
                        let e2eLatency = Date().timeIntervalSince1970 - timestamp
                        logger.trace("End-to-end latency", metadata: [
                            "latency": "\(String(format: "%.3f", e2eLatency))s"
                        ])
                    }

                    // Acknowledge message
                    try await consumer.acknowledge(message)
                    messageCount += 1

                    // Log progress
                    if messageCount % 1000 == 0 {
                        let actualRate = calculateActualRate()
                        logger.info("Consumption progress", metadata: [
                            "messagesReceived": "\(messageCount)",
                            "actualRate": "\(String(format: "%.2f", actualRate)) msg/s"
                        ])
                    }
                }

            } catch {
                logger.error("Failed to process message", metadata: [
                    "error": "\(error)",
                    "messageCount": "\(messageCount)"
                ])
            }
        }

        let actualRate = calculateActualRate()
        logger.info("Consumption completed", metadata: [
            "totalReceived": "\(messageCount)",
            "duration": "\(Date().timeIntervalSince(startTime ?? Date()))s",
            "averageRate": "\(String(format: "%.2f", actualRate)) msg/s"
        ])
    }

    private func processMessage(_ message: Message<String>) {
        // Simulate message processing

        if !message.properties.isEmpty {
            logger.trace("Message properties", metadata: [
                "properties": "\(message.properties)"
            ])
        }
    }

    private func parseMessage(_ messageContent: String) -> [String: Any]? {
        guard let data = messageContent.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    private func calculateActualRate() -> Double {
        guard let startTime = startTime else { return 0 }
        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return Double(messageCount) / duration
    }

    public func getStatistics() async -> ConsumerStatistics {
        let idleTime: TimeInterval?
        if let lastMessageTime = lastMessageTime {
            idleTime = Date().timeIntervalSince(lastMessageTime)
        } else {
            idleTime = nil
        }

        return ConsumerStatistics(
            messagesReceived: messageCount,
            actualRate: calculateActualRate(),
            isRunning: isRunning,
            idleTime: idleTime
        )
    }
}

public struct ConsumerStatistics: Sendable {
    public let messagesReceived: Int
    public let actualRate: Double
    public let isRunning: Bool
    public let idleTime: TimeInterval?
}