# Caching Middleware

> High-performance in-memory caching middleware with advanced eviction strategies (LRU, SIEVE) and stampede prevention mechanisms (Request Coalescing, Probabilistic Early Refresh).

## 🚀 Features

### Eviction Strategies
- **LRU (Least Recently Used)**: Classic eviction using `LinkedHashMap` for O(1) operations
- **SIEVE**: Modern queue-based eviction with visited bit tracking for improved efficiency

### Refresh Strategies
- **Naive TTL**: Simple time-to-live based expiration
- **Request Coalescing**: Prevents cache stampede by coalescing concurrent requests for the same key
- **Probabilistic Early Refresh (PER)**: Proactively refreshes popular entries before expiration

### Observability
- Real-time metrics via HTTP endpoints
- Detailed hit/miss ratio tracking
- Backend request monitoring
- Performance analytics

### Load Testing
- Built-in load generator with multiple scenarios
- Zipfian distribution for realistic workload simulation
- Stampede scenario testing
- Mixed workload patterns

## 📋 Prerequisites

- **Java**: 17 or higher
- **Maven**: 3.6 or higher

## 🛠️ Quick Start

### 1. Build the Project

```bash
mvn clean package
```

### 2. Start the Server

```bash
java -jar target/caching-middleware-0.0.1-SNAPSHOT.jar
```

The server will start on `http://localhost:8080`

### 3. Configure Cache Mode

```bash
# Example: LRU with Naive TTL (capacity=100, ttl=5000ms)
curl "http://localhost:8080/config?mode=M1&capacity=100&ttl=5000"
```

### 4. Run Load Tests

```bash
# Scenario A: Memory Constrained (60 seconds)
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="A 60"

# Scenario B: Cache Stampede (30 seconds)
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="B 30"

# Scenario C: Mixed Workload (60 seconds)
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="C 60"
```

## 🎯 Cache Modes

| Mode | Eviction | Refresh Strategy | Use Case |
|------|----------|------------------|----------|
| **M1** | LRU | Naive TTL | General purpose caching |
| **M2** | LRU | Request Coalescing | High-concurrency scenarios |
| **M3** | LRU | Probabilistic Early Refresh | Popular content with predictable access |
| **M4** | SIEVE | Naive TTL | Memory-efficient eviction |
| **M5** | SIEVE | Probabilistic Early Refresh | Optimal performance for hot data |

## 📡 API Endpoints

### Configuration

**Switch Cache Mode**
```bash
GET /config?mode={MODE}&capacity={CAPACITY}&ttl={TTL_MS}
```

**Parameters:**
- `mode`: Cache mode (M1-M5)
- `capacity`: Maximum cache entries (default: 100)
- `ttl`: Time-to-live in milliseconds (default: 5000)

**Example:**
```bash
curl "http://localhost:8080/config?mode=M3&capacity=200&ttl=10000"
```

### Monitoring

**Get Statistics**
```bash
GET /stats
```

Returns JSON with cache performance metrics:
```json
{
  "hits": 850,
  "misses": 150,
  "hitRatio": 0.85,
  "backendRequests": 200,
  "totalRequests": 1000
}
```

**Reset Cache**
```bash
GET /reset
```

Clears all cache entries and resets statistics.

## 🧪 Running Experiments

### Automated Test Scripts

The repository includes shell scripts for comprehensive testing:

```bash
# Run all Scenario A configurations
./run_scenario_a_comprehensive.sh

# Run all Scenario B configurations
./run_scenario_b_comprehensive.sh

# Run all Scenario C configurations
./run_scenario_c_comprehensive.sh

# Run complete experiment suite
./run_experiments.sh
```

### Manual Experiment Workflow

1. **Start the server**
   ```bash
   java -jar target/caching-middleware-0.0.1-SNAPSHOT.jar
   ```

2. **Configure cache mode**
   ```bash
   curl "http://localhost:8080/config?mode=M1&capacity=100&ttl=5000"
   ```

3. **Run load generator**
   ```bash
   mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" \
     -Dexec.args="A 60"
   ```

4. **Collect metrics**
   ```bash
   curl "http://localhost:8080/stats"
   ```

5. **Reset for next test**
   ```bash
   curl "http://localhost:8080/reset"
   ```

## 📊 Load Generator Scenarios

### Scenario A: Memory Constrained
- **Purpose**: Test eviction strategy efficiency
- **Pattern**: Zipfian distribution (α=1.5)
- **Cache Size**: Small relative to working set
- **Duration**: 60 seconds

### Scenario B: Cache Stampede
- **Purpose**: Test stampede prevention mechanisms
- **Pattern**: Synchronized burst requests for expired keys
- **Focus**: Request coalescing effectiveness
- **Duration**: 30 seconds

### Scenario C: Mixed Workload
- **Purpose**: Realistic production-like traffic
- **Pattern**: Combination of hot and cold data access
- **Metrics**: Overall system performance
- **Duration**: 60 seconds

## 🏗️ Architecture

```
src/main/java/com/example/cache/
├── api/
│   └── CacheController.java          # REST API endpoints
├── core/
│   ├── CacheService.java             # Main cache logic
│   └── CacheEntry.java               # Cache entry model
├── eviction/
│   ├── EvictionStrategy.java         # Eviction interface
│   ├── LruEvictionStrategy.java      # LRU implementation
│   └── SieveEvictionStrategy.java    # SIEVE implementation
├── refresh/
│   ├── RefreshStrategy.java          # Refresh interface
│   ├── NaiveTtlRefreshStrategy.java  # Simple TTL
│   ├── CoalescingRefreshStrategy.java # Stampede prevention
│   └── ProbabilisticEarlyRefreshStrategy.java # PER
├── backend/
│   └── MockBackend.java              # Simulated backend
└── loadgen/
    ├── LoadGenerator.java            # Load testing tool
    └── ScenarioERunner.java          # Scenario executor
```

## 📈 Performance Metrics

The middleware tracks:
- **Cache Hit Ratio**: Percentage of requests served from cache
- **Backend Requests**: Number of backend calls (lower is better)
- **Latency**: Response time distribution
- **Eviction Count**: Number of entries evicted

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📄 License

This project is available for educational and research purposes.

## 🔗 Related Documentation

- [Final Report](final_report.md) - Comprehensive analysis and experimental results
- [Implementation Details](report_sections_1_3.md.resolved) - Technical deep dive

---

**Built with ❤️ for high-performance caching research**
