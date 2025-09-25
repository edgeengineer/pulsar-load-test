import Foundation
import ArgumentParser
import PulsarClient
import Logging
import Metrics

@main
struct PulsarLoadTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pulsar-load-test",
        abstract: "Load testing tool for the Pulsar Client",
        version: "1.0.0"
    )

    @Option(name: .shortAndLong, help: "Run mode: consumer, producer, or both")
    var mode: String = "both"

    @Option(name: .shortAndLong, help: "Message rate (e.g., '10/minute', '60/second', '100/hour')")
    var rate: String = "10/second"

    @Option(name: .shortAndLong, help: "Test duration (e.g., '30s', '10m', '2h', '1d', '1w')")
    var duration: String = "1m"

    @Option(name: .shortAndLong, help: "Pulsar service URL")
    var serviceUrl: String = "pulsar://localhost:6650"

    @Option(name: .shortAndLong, help: "Topic name")
    var topic: String = "persistent://public/default/load-test"

    @Option(name: .shortAndLong, help: "Subscription name (for consumer)")
    var subscription: String = "load-test-subscription"

    @Option(name: .shortAndLong, help: "Prometheus metrics port")
    var prometheusPort: Int = 9090

    @Option(name: .shortAndLong, help: "Device ID (auto-generated if not provided)")
    var deviceId: String?

    @Option(name: .shortAndLong, help: "Message size in bytes")
    var messageSize: Int = 1024

    @Option(name: .shortAndLong, help: "Log level: trace, debug, info, warning, error, critical")
    var logLevel: String = "info"

    @Flag(name: .long, help: "Enable verbose logging")
    var verbose: Bool = false

    mutating func run() async throws {
        // Configure logging
        let loggerLevel = parseLogLevel(verbose ? "debug" : logLevel)
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        var logger = Logger(label: "pulsar-load-test")
        logger.logLevel = loggerLevel

        logger.info("Starting Pulsar Load Test", metadata: [
            "version": "1.0.0",
            "pid": "\(ProcessInfo.processInfo.processIdentifier)"
        ])

        // Parse configuration
        let runMode = try parseRunMode(mode)
        let messageRate = try MessageRate.parse(rate)
        let testDuration = try parseDuration(duration)

        let configuration = LoadTestConfiguration(
            mode: runMode,
            messageRate: messageRate,
            duration: testDuration,
            topic: topic,
            subscription: subscription,
            serviceUrl: serviceUrl,
            prometheusPort: prometheusPort,
            deviceId: deviceId,
            messageSize: messageSize
        )

        configuration.logConfiguration(to: logger)

        // Initialize metrics
        let metricsManager = try await MetricsManager(
            port: prometheusPort,
            deviceId: configuration.deviceId,
            logger: logger
        )

        // Initialize Pulsar client
        let client = PulsarClient.builder { builder in
            builder.withServiceUrl(serviceUrl)
        }

        logger.info("Pulsar client initialized", metadata: [
            "serviceUrl": "\(serviceUrl)"
        ])

        // Create test coordinator
        let coordinator = LoadTestCoordinator(
            configuration: configuration,
            client: client,
            metricsManager: metricsManager,
            logger: logger
        )

        // Run the load test
        do {
            try await coordinator.run()
            logger.info("Load test completed successfully")
        } catch {
            logger.error("Load test failed", metadata: [
                "error": "\(error)"
            ])
            throw error
        }

        // Clean shutdown
        await coordinator.shutdown()
        await metricsManager.shutdown()
        await client.dispose()
    }

    private func parseRunMode(_ mode: String) throws -> RunMode {
        guard let runMode = RunMode(rawValue: mode.lowercased()) else {
            throw ValidationError("Invalid run mode: '\(mode)'. Use 'consumer', 'producer', or 'both'")
        }
        return runMode
    }

    private func parseDuration(_ durationString: String) throws -> TimeInterval {
        let pattern = #"^(\d+)([smhdw])$"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)

        guard let match = regex.firstMatch(
            in: durationString,
            options: [],
            range: NSRange(location: 0, length: durationString.utf16.count)
        ) else {
            throw ConfigurationError.invalidDuration(durationString)
        }

        let valueRange = Range(match.range(at: 1), in: durationString)!
        let unitRange = Range(match.range(at: 2), in: durationString)!

        guard let value = Int(durationString[valueRange]) else {
            throw ConfigurationError.invalidDuration(durationString)
        }

        let unit = durationString[unitRange].lowercased()

        switch unit {
        case "s": return TimeInterval(value)
        case "m": return TimeInterval(value * 60)
        case "h": return TimeInterval(value * 3600)
        case "d": return TimeInterval(value * 86400)
        case "w": return TimeInterval(value * 604800)
        default:
            throw ConfigurationError.invalidDuration(durationString)
        }
    }

    private func parseLogLevel(_ level: String) -> Logger.Level {
        switch level.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warning", "warn": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }
}