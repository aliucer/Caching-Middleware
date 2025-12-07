# High-Performance Caching Middleware

A Java-based in-memory caching middleware implementing modern eviction (SIEVE) and stampede prevention (PER, Coalescing) algorithms.

## Features
- **Eviction**: LRU (LinkedHashMap), SIEVE (Queue + Visited Bit).
- **Refresh**: Naive TTL, Request Coalescing, Probabilistic Early Refresh (PER).
- **Observability**: Metric endpoints for hit/miss/request analysis.
- **Load Generation**: Built-in tool for Zipfian and Stampede workload simulation.

## Getting Started

### Prerequisites
- Java 17+
- Maven 3+

### Build
```bash
mvn clean package
```

### Run Server
```bash
java -jar target/caching-middleware-0.0.1-SNAPSHOT.jar
```

### Run Load Generator
```bash
# Scenario A: Memory Constrained (Duration 60s)
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="A 60"

# Scenario B: Stampede
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="B 30"

# Scenario C: Mixed Workload
mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="C 60"
```

## Configuration Endpoints
- **Switch Mode**: `GET /config?mode={MODE}&capacity={CAP}&ttl={TTL}`
    - Modes: `M1` (LRU+Naive), `M2` (LRU+Coalescing), `M3` (LRU+PER), `M4` (SIEVE+Naive), `M5` (SIEVE+PER).
- **Statistics**: `GET /stats`
- **Reset**: `GET /reset`

## Experiment Workflow
1. Start Server.
2. Select Mode (e.g., `curl "http://localhost:8080/config?mode=M1"`).
3. Run Load Generator (e.g., `mvn exec:java ... -Dexec.args="A 60"`).
4. Record metrics from output and `/stats`.
5. Reset (`/reset`) and repeat for next mode.
