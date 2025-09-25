import Foundation
import PulsarClient
import Logging
import Metrics

/// Coordinates the load test execution
public actor LoadTestCoordinator {
    private let configuration: LoadTestConfiguration
    private let client: PulsarClient
    private let metricsManager: MetricsManager
    private let logger: Logger

    private var producer: LoadTestProducer?
    private var consumer: LoadTestConsumer?
    private var monitorTask: Task<Void, Never>?
    private var startTime: Date?
    private var isRunning = false

    public init(
        configuration: LoadTestConfiguration,
        client: PulsarClient,
        metricsManager: MetricsManager,
        logger: Logger
    ) {
        self.configuration = configuration
        self.client = client
        self.metricsManager = metricsManager
        self.logger = logger
    }

    public func run() async throws {
        guard !isRunning else {
            logger.warning("Load test already running")
            return
        }

        isRunning = true
        logger.info("Starting load test coordinator", metadata: [
            "mode": "\(configuration.mode.description)"
        ])

        // Initialize components based on mode
        switch configuration.mode {
        case .producer:
            try await runProducerOnly()
        case .consumer:
            try await runConsumerOnly()
        case .both:
            try await runBoth()
        }

        logger.info("Load test completed")
    }

    private func runProducerOnly() async throws {
        logger.info("Running in Producer-Only mode")

        producer = LoadTestProducer(
            configuration: configuration,
            client: client,
            logger: logger
        )

        try await producer?.start()

        // Start monitoring
        startMonitoring()

        // Wait for test duration
        try await waitForCompletion()
    }

    private func runConsumerOnly() async throws {
        logger.info("Running in Consumer-Only mode")

        consumer = LoadTestConsumer(
            configuration: configuration,
            client: client,
            logger: logger
        )

        try await consumer?.start()

        // Start monitoring
        startMonitoring()

        // Wait for test duration
        try await waitForCompletion()
    }

    private func runBoth() async throws {
        logger.info("Running in Producer and Consumer mode")

        producer = LoadTestProducer(
            configuration: configuration,
            client: client,
            logger: logger
        )

        consumer = LoadTestConsumer(
            configuration: configuration,
            client: client,
            logger: logger
        )

        // Start both components
        try await producer?.start()
        try await consumer?.start()

        // Start monitoring
        startMonitoring()

        // Wait for test duration
        try await waitForCompletion()
    }

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            await self?.monitorProgress()
        }
    }

    private func monitorProgress() async {
        let interval: TimeInterval = 30 // Report every 30 seconds
        startTime = Date()

        while isRunning {
            try? await Task.sleep(for: .seconds(interval))

            guard isRunning else { break }

            // Gather statistics
            var metadata: Logger.Metadata = [:]

            if let producer = producer {
                let stats = await producer.getStatistics()
                metadata["producer.sent"] = .string("\(stats.messagesSent)")
                metadata["producer.rate"] = .string("\(String(format: "%.2f", stats.actualRate)) msg/s")
            }

            if let consumer = consumer {
                let stats = await consumer.getStatistics()
                metadata["consumer.received"] = .string("\(stats.messagesReceived)")
                metadata["consumer.rate"] = .string("\(String(format: "%.2f", stats.actualRate)) msg/s")

                if let idleTime = stats.idleTime {
                    metadata["consumer.idle"] = .string("\(String(format: "%.2f", idleTime))s")
                }
            }

            // Calculate remaining time
            let elapsed = startTime?.timeIntervalSince1970 ?? 0
            let remaining = max(0, configuration.duration - elapsed)
            metadata["elapsed"] = .string(formatDuration(elapsed))
            metadata["remaining"] = .string(formatDuration(remaining))

            logger.info("Load test progress", metadata: metadata)
        }
    }

    private func waitForCompletion() async throws {
        logger.info("Waiting for test completion", metadata: [
            "duration": "\(formatDuration(configuration.duration))"
        ])

        try await Task.sleep(for: .seconds(configuration.duration))

        logger.info("Test duration reached, stopping components")
    }

    public func shutdown() async {
        guard isRunning else { return }

        logger.info("Shutting down load test coordinator")
        isRunning = false

        // Cancel monitoring
        monitorTask?.cancel()

        // Stop components
        await producer?.stop()
        await consumer?.stop()

        logger.info("Coordinator shutdown complete")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}