#!/bin/bash
set -e

# Setup Env
export JAVA_HOME=~/tools/jdk-17.0.2
export PATH=$JAVA_HOME/bin:~/tools/apache-maven-3.9.6/bin:$PATH

WORKDIR="/home/ali/cmpe273/caching-middleware"
cd $WORKDIR

echo ">>> Building Project..."
mvn clean package -DskipTests -q

# Configuration Constants
TOTAL_KEYS=100000
HOT_KEYS=1000        # 1% of total keys are "hot"
CACHE_CAPACITY=2000  # 2% of universe, 2x hot set
TTL=30000            # 30 seconds
BACKEND_LATENCY=100  # 100ms backend (realistic)

# Phase Configuration (seconds)
# Phase 1: Low Load (60s) - Warm up
# Phase 2: Normal Load (120s) - Steady state  
# Phase 3: Burst (60s) - Stress test
# Phase 4: Recovery (120s) - Back to normal
PHASE_DURATIONS="60,120,60,120"  # Total: 6 minutes
PHASE_THREADS="50,200,500,200"   # Low -> Normal -> Burst -> Normal

run_comprehensive_test() {
    MODE=$1
    HOT_RATIO=$2
    DESC=$3

    echo ""
    echo "============================================================"
    echo "=== TEST: $DESC ==="
    echo "=== Mode: $MODE | HotRatio: $HOT_RATIO ==="
    echo "============================================================"

    # Kill any existing server
    pkill -f "caching-middleware" || true
    sleep 2

    # Start Server
    java -Xmx2G -jar target/caching-middleware-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
    SERVER_PID=$!
    echo "Server PID: $SERVER_PID"
    sleep 8

    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CACHE_CAPACITY&ttl=$TTL&latency=$BACKEND_LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    echo "Configured: Mode=$MODE, Capacity=$CACHE_CAPACITY, TTL=${TTL}ms, Latency=${BACKEND_LATENCY}ms"

    # Run Multi-Phase Test via Java directly (faster compilation already done)
    java -cp target/classes:$(mvn dependency:build-classpath -q -DincludeScope=runtime -Dmdep.outputFile=/dev/stdout) \
        com.example.cache.loadgen.ScenarioERunner \
        $TOTAL_KEYS $HOT_KEYS $HOT_RATIO "$PHASE_DURATIONS" "$PHASE_THREADS" 2>&1 | tee scenario_e_output.txt

    # Capture Final Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    C_SIZE=$(echo $STATS | grep -o 'cacheSize":[0-9]*' | grep -o '[0-9]*')
    
    echo ""
    echo "=== BACKEND SUMMARY ==="
    echo "Backend Requests: $B_REQS"
    echo "Final Cache Size: $C_SIZE"

    # Stop Server
    kill $SERVER_PID 2>/dev/null || true
    sleep 2
}

echo "=========================================="
echo "=== SCENARIO C: COMPREHENSIVE TEST ==="
echo "=========================================="
echo "Configuration:"
echo "  Total Keys: $TOTAL_KEYS"
echo "  Hot Keys: $HOT_KEYS (1%)"
echo "  Cache Capacity: $CACHE_CAPACITY (2%)"
echo "  TTL: ${TTL}ms"
echo "  Backend Latency: ${BACKEND_LATENCY}ms"
echo "  Phases: $PHASE_DURATIONS"
echo "  Threads: $PHASE_THREADS"
echo ""

# Test Matrix
# Vary Hot Ratio to show algorithm effectiveness

echo ">>> Running Hot Ratio Sensitivity Analysis <<<"

# 1. Standard Pareto (80/20)
run_comprehensive_test "M1" "0.8" "LRU+Naive (80/20)"
run_comprehensive_test "M5" "0.8" "SIEVE+PER (80/20)"

# 2. Skewed (90/10)
run_comprehensive_test "M1" "0.9" "LRU+Naive (90/10)"
run_comprehensive_test "M5" "0.9" "SIEVE+PER (90/10)"

# 3. Highly Skewed (95/5)
run_comprehensive_test "M1" "0.95" "LRU+Naive (95/5)"
run_comprehensive_test "M5" "0.95" "SIEVE+PER (95/5)"

# 4. Extreme Skew (99/1)
run_comprehensive_test "M1" "0.99" "LRU+Naive (99/1)"
run_comprehensive_test "M5" "0.99" "SIEVE+PER (99/1)"

# 5. NoCache Baseline (for reference, only 80/20)
run_comprehensive_test "M0" "0.8" "NoCache (80/20)"

echo ""
echo ">>> All Tests Complete <<<"
