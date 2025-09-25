import XCTest
@testable import PulsarLoadTest

final class ConfigurationTests: XCTestCase {
    func testMessageRateParsing() throws {
        // Test seconds
        let rate1 = try MessageRate.parse("10/second")
        XCTAssertEqual(rate1.messagesPerInterval, 10)
        XCTAssertEqual(rate1.interval, 1)
        XCTAssertEqual(rate1.messagesPerSecond, 10)

        // Test minutes
        let rate2 = try MessageRate.parse("60/minute")
        XCTAssertEqual(rate2.messagesPerInterval, 60)
        XCTAssertEqual(rate2.interval, 60)
        XCTAssertEqual(rate2.messagesPerSecond, 1)

        // Test hours
        let rate3 = try MessageRate.parse("3600/hour")
        XCTAssertEqual(rate3.messagesPerInterval, 3600)
        XCTAssertEqual(rate3.interval, 3600)
        XCTAssertEqual(rate3.messagesPerSecond, 1)
    }

    func testInvalidMessageRate() {
        XCTAssertThrowsError(try MessageRate.parse("invalid"))
        XCTAssertThrowsError(try MessageRate.parse("10"))
        XCTAssertThrowsError(try MessageRate.parse("/second"))
    }

    func testRunModeDescription() {
        XCTAssertEqual(RunMode.consumer.description, "Consumer Only")
        XCTAssertEqual(RunMode.producer.description, "Producer Only")
        XCTAssertEqual(RunMode.both.description, "Producer and Consumer")
    }

    func testConfigurationTotalMessages() {
        let config = LoadTestConfiguration(
            mode: .producer,
            messageRate: MessageRate(messagesPerInterval: 10, interval: 1),
            duration: 60,
            topic: "test",
            subscription: "test-sub",
            serviceUrl: "pulsar://localhost:6650",
            prometheusPort: 9090
        )

        XCTAssertEqual(config.totalMessages, 600)
    }
}