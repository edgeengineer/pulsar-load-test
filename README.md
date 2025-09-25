# Pulsar Load Testing Tool

A sophisticated load testing tool for Apache Pulsar with integrated Prometheus metrics, designed for long-running distributed tests across multiple devices.

## Features

- **Multiple Run Modes**: Consumer-only, Producer-only, or Both modes
- **Configurable Message Rates**: Support for messages per second/minute/hour
- **Long-Running Tests**: Designed for tests running 48+ hours
- **Prometheus Integration**: Automatic metrics export with zero configuration
- **Multi-Device Support**: Coordinate tests across multiple devices simultaneously
- **Swift 6 Compliant**: Built with modern Swift concurrency and safety features
- **Comprehensive Metrics**: Track send/receive rates, latencies, errors, and more

## Installation

### Prerequisites

- Swift 6.1 or later
- Apache Pulsar instance running (local or remote)
- macOS 13+ or Linux (Ubuntu 20.04+)

### Building

```bash
cd PulsarTesting
swift build -c release
```

The executable will be available at `.build/release/pulsar-load-test`

### Installing (Optional)

```bash
# Copy to a location in your PATH
cp .build/release/pulsar-load-test /usr/local/bin/
```

## Usage

### Basic Examples

#### Producer-Only Mode (10 messages/second for 1 hour)
```bash
pulsar-load-test \
  --mode producer \
  --rate "10/second" \
  --duration "1h" \
  --service-url "pulsar://localhost:6650" \
  --topic "persistent://public/default/load-test"
```

#### Consumer-Only Mode
```bash
pulsar-load-test \
  --mode consumer \
  --duration "1h" \
  --service-url "pulsar://localhost:6650" \
  --topic "persistent://public/default/load-test" \
  --subscription "test-subscription"
```

#### Both Mode (Producer and Consumer)
```bash
pulsar-load-test \
  --mode both \
  --rate "60/minute" \
  --duration "48h" \
  --service-url "pulsar://localhost:6650" \
  --topic "persistent://public/default/load-test"
```

### Command-Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--mode` | `-m` | Run mode: `consumer`, `producer`, or `both` | `both` |
| `--rate` | `-r` | Message rate (e.g., `10/second`, `60/minute`, `100/hour`) | `10/second` |
| `--duration` | `-d` | Test duration (e.g., `30s`, `10m`, `2h`, `1d`, `1w`) | `1m` |
| `--service-url` | `-s` | Pulsar service URL | `pulsar://localhost:6650` |
| `--topic` | `-t` | Topic name | `persistent://public/default/load-test` |
| `--subscription` | | Subscription name (for consumer) | `load-test-subscription` |
| `--prometheus-port` | `-p` | Prometheus metrics port | `9090` |
| `--device-id` | | Device identifier (auto-generated if not set) | `<hostname>-<timestamp>` |
| `--message-size` | | Message size in bytes | `1024` |
| `--log-level` | `-l` | Log level: `trace`, `debug`, `info`, `warning`, `error`, `critical` | `info` |
| `--verbose` | | Enable verbose logging | `false` |

### Message Rate Format

- `N/second` or `N/s` - N messages per second
- `N/minute` or `N/m` - N messages per minute
- `N/hour` or `N/h` - N messages per hour

Examples:
- `10/second` - 10 messages per second
- `600/minute` - 600 messages per minute (10 per second)
- `36000/hour` - 36000 messages per hour (10 per second)

### Duration Format

- `Ns` - N seconds
- `Nm` - N minutes
- `Nh` - N hours
- `Nd` - N days
- `Nw` - N weeks

Examples:
- `30s` - 30 seconds
- `10m` - 10 minutes
- `2h` - 2 hours
- `1d` - 1 day (24 hours)
- `1w` - 1 week (7 days)

## Metrics

The tool automatically exposes Prometheus metrics on the configured port (default: 9090).

### Accessing Metrics

```bash
curl http://localhost:9090/metrics
```

### Available Metrics

#### Test Metrics
- `pulsar.test.start_time` - Test start timestamp
- `pulsar.test.duration_seconds` - Configured test duration
- `pulsar.test.configured_rate` - Configured message rate
- `pulsar.test.actual_rate` - Actual achieved message rate
- `pulsar.test.status` - Test status (1=running, 2=completed, 3=failed)
- `pulsar.test.errors` - Error count

#### PulsarClient Metrics (Automatic)
All standard PulsarClient metrics are automatically emitted:

**Client Metrics:**
- `pulsar.client.connections.active`
- `pulsar.client.connections.total`
- `pulsar.client.connections.failed`
- `pulsar.client.lookup.requests`
- `pulsar.client.lookup.latency`

**Producer Metrics:**
- `pulsar.producer.messages.sent`
- `pulsar.producer.messages.failed`
- `pulsar.producer.messages.pending`
- `pulsar.producer.send.latency`
- `pulsar.producer.batch.size`

**Consumer Metrics:**
- `pulsar.consumer.messages.received`
- `pulsar.consumer.messages.acknowledged`
- `pulsar.consumer.messages.nacked`
- `pulsar.consumer.receive.latency`
- `pulsar.consumer.process.latency`
- `pulsar.consumer.backlog`

## Multi-Device Testing

### Coordinated Testing Across Devices

1. **Start Prometheus** on a central monitoring server:
```bash
# prometheus.yml configuration
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'pulsar-load-test'
    static_configs:
      - targets: ['device1:9090', 'device2:9090', 'device3:9090']
```

2. **Run tests on multiple devices** with unique device IDs:

Device 1 (Producer):
```bash
pulsar-load-test \
  --mode producer \
  --device-id "device-1" \
  --rate "100/second" \
  --duration "48h"
```

Device 2 (Consumer):
```bash
pulsar-load-test \
  --mode consumer \
  --device-id "device-2" \
  --subscription "test-sub-1" \
  --duration "48h"
```

Device 3 (Both):
```bash
pulsar-load-test \
  --mode both \
  --device-id "device-3" \
  --rate "50/second" \
  --duration "48h"
```

## Message Structure

Messages contain JSON payloads with:
- `device_id`: Source device identifier
- `sequence`: Message sequence number
- `timestamp`: Unix timestamp when sent
- `test_run`: Test run identifier
- `data`: Padding to reach configured message size

Example:
```json
{
  "device_id": "device-1",
  "sequence": 12345,
  "timestamp": 1702934567.123,
  "test_run": "1702934500.0",
  "data": "xxx..."
}
```

## Troubleshooting

### Connection Issues

```bash
# Test connectivity
pulsar-load-test \
  --mode producer \
  --rate "1/second" \
  --duration "10s" \
  --log-level debug
```

### High Memory Usage

Reduce batch sizes or receiver queue size in the code:
- `withBatchingMaxMessages(50)` (default: 100)
- `withReceiverQueueSize(500)` (default: 1000)

### Metrics Not Appearing

1. Check Prometheus port is accessible:
```bash
curl http://localhost:9090/metrics
```

2. Verify no port conflicts:
```bash
lsof -i :9090
```
