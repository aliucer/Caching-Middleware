# Caching Middleware

A Java-based caching middleware implementing modern eviction algorithms (LRU, SIEVE) and stampede prevention strategies (Coalescing, Probabilistic Early Refresh).

Built for CMPE 273 - Enterprise Distributed Systems.

## Features

**Eviction Strategies:**
- **LRU** - Least Recently Used with LinkedHashMap
- **SIEVE** - Lazy promotion + quick demotion (NSDI'24)

**Refresh Strategies:**
- **Naive TTL** - Simple expiration
- **Coalescing** - Prevents thundering herd via `computeIfAbsent`
- **PER** - Probabilistic Early Refresh (VLDB'15)

## Quick Start

```bash
# Build
mvn clean package

# Run server
java -jar target/caching-middleware-0.0.1-SNAPSHOT.jar

# Configure mode (in another terminal)
curl "http://localhost:8080/config?mode=M1&capacity=100&ttl=5000"

# Test cache
curl "http://localhost:8080/item?key=mykey"

# View stats
curl "http://localhost:8080/stats"
```

## Cache Modes

| Mode | Eviction | Refresh | Best For |
|------|----------|---------|----------|
| M0 | - | - | No cache (baseline) |
| M1 | LRU | Naive | General use |
| M2 | LRU | Coalescing | High concurrency |
| M3 | LRU | PER | Low latency |
| M4 | SIEVE | Naive | Scan resistance |
| M5 | SIEVE | PER | Best overall |

## API

| Endpoint | Description |
|----------|-------------|
| `GET /item?key={key}` | Get cached item |
| `GET /config?mode={M1-M5}&capacity={n}&ttl={ms}` | Configure cache |
| `GET /stats` | View metrics |
| `GET /reset` | Clear cache |

## Demo Scripts

```bash
# SIEVE vs LRU scan resistance
./scripts/demo1_sieve_vs_lru.sh

# Stampede: Naive vs Coalescing
./scripts/demo2_stampede.sh
```

## Documentation

- [Interactive Presentation](docs/presentation.html) - Open in browser
- [Technical Report](docs/final_report.md) - Detailed analysis

## Project Structure

```
src/main/java/com/example/cache/
├── api/           # REST endpoints
├── core/          # CacheService, CacheEntry
├── eviction/      # LRU, SIEVE implementations
├── refresh/       # Naive, Coalescing, PER
├── backend/       # Mock backend with latency
└── loadgen/       # Load testing tools
```

## References

- Zhang et al. "SIEVE: A Turn-Key Eviction Algorithm" (NSDI'24)
- Vattani et al. "Optimal Cache Stampede Prevention" (VLDB'15)

