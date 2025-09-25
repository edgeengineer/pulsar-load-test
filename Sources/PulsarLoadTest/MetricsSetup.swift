import Foundation
import Metrics
import Prometheus
import Logging

public actor MetricsManager {
    private let port: Int
    private let logger: Logger

    public init(port: Int, deviceId: String, logger: Logger) async throws {
        self.port = port
        self.logger = logger

        // Bootstrap Prometheus metrics
        let prometheus = PrometheusMetricsFactory()
        MetricsSystem.bootstrap(prometheus)
    }

    public func shutdown() async {
        logger.info("Metrics manager shutdown")
    }
}