#!/bin/bash
set -e

# Setup Env
export JAVA_HOME=~/tools/jdk-17.0.2
export PATH=$JAVA_HOME/bin:~/tools/apache-maven-3.9.6/bin:$PATH

WORKDIR="/home/ali/cmpe273/caching-middleware"
cd $WORKDIR

echo ">>> Building Project..."
mvn clean package -DskipTests -q

# Kill any existing server
pkill -f "caching-middleware" || true
sleep 2

echo ">>> Starting Server..."
java -Xmx2G -jar target/caching-middleware-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 10

# Test duration
DURATION=30

run_test() {
    MODE=$1
    LATENCY=$2
    TTL=$3
    THREADS=$4
    DESC=$5

    CAPACITY=100
    
    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Lat: ${LATENCY}ms | TTL: ${TTL}ms | Threads: $THREADS"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="B $DURATION $THREADS" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    P99=$(grep -o 'P99=[0-9.]*' loadgen.out | cut -d= -f2 | sed 's/ms//' || echo "0")
    MAX=$(grep -o 'Max=[0-9.]*' loadgen.out | cut -d= -f2 | sed 's/ms//' || echo "0")
    
    # Calculate
    LOAD_RATIO="0"
    RPS="0"
    if [ "$T_REQS" -gt 0 ]; then
       LOAD_RATIO=$(echo "scale=2; $B_REQS / $T_REQS * 100" | bc)
       RPS=$(echo "scale=1; $T_REQS / $DURATION" | bc)
    fi
     
    echo "Result: RPS=$RPS, Total=$T_REQS, Backend=$B_REQS, Load=${LOAD_RATIO}%, P99=${P99}ms, Max=${MAX}ms"
    echo "--------------------------------------------------------"
}

run_comparison() {
    LAT=$1
    TTL=$2
    TH=$3
    NAME=$4
    
    echo ""
    echo "============================================================"
    echo "=== CASE: $NAME ==="
    echo "=== Latency=${LAT}ms | TTL=${TTL}ms | Threads=$TH ==="
    echo "============================================================"
    
    # M0: NoCache
    run_test "M0" "$LAT" "$TTL" "$TH" "NoCache"
    
    # M1: Naive
    run_test "M1" "$LAT" "$TTL" "$TH" "LRU+Naive"
    
    # M2: Coalescing
    run_test "M2" "$LAT" "$TTL" "$TH" "LRU+Coalescing"
    
    # M3: PER
    run_test "M3" "$LAT" "$TTL" "$TH" "LRU+PER"
}

echo "=========================================="
echo "=== SCENARIO B: COMPREHENSIVE STAMPEDE ==="
echo "=========================================="
echo "Duration: ${DURATION}s per test"
echo ""

# =============================================================================
# SECTION 1: THREAD SCALING (Fixed Latency/TTL, Vary Concurrency)
# =============================================================================
echo ""
echo "########## SECTION 1: THREAD SCALING ##########"
echo "Fixed: Latency=100ms, TTL=1000ms"
echo ""

run_comparison "100" "1000" "50" "Light Load (50 Threads)"
run_comparison "100" "1000" "100" "Standard (100 Threads)"
run_comparison "100" "1000" "200" "Medium (200 Threads)"
run_comparison "100" "1000" "500" "Heavy (500 Threads)"
run_comparison "100" "1000" "1000" "Massive (1000 Threads)"

# =============================================================================
# SECTION 2: LATENCY/TTL RATIO (Fixed Threads, Vary Timing)
# =============================================================================
echo ""
echo "########## SECTION 2: LATENCY/TTL RATIO ##########"
echo "Fixed: Threads=200"
echo ""

# Safe: Latency << TTL (plenty of buffer)
run_comparison "50" "2000" "200" "Safe (Lat=50ms, TTL=2000ms)"

# Normal: Latency = 10% of TTL
run_comparison "100" "1000" "200" "Normal (Lat=100ms, TTL=1000ms)"

# Tight: Latency = 50% of TTL
run_comparison "250" "500" "200" "Tight (Lat=250ms, TTL=500ms)"

# Edge: Latency ≈ TTL
run_comparison "400" "500" "200" "Edge (Lat=400ms, TTL=500ms)"

# Death Spiral: Latency > TTL
run_comparison "500" "200" "200" "Death Spiral (Lat=500ms, TTL=200ms)"

# Extreme Death: Latency >> TTL
run_comparison "1000" "100" "200" "Extreme Death (Lat=1000ms, TTL=100ms)"

# =============================================================================
# SECTION 3: SLOW BACKEND SCALING
# =============================================================================
echo ""
echo "########## SECTION 3: SLOW BACKEND SCALING ##########"
echo "Fixed: Threads=100, TTL=5000ms (5s)"
echo ""

run_comparison "100" "5000" "100" "Fast Backend (100ms)"
run_comparison "500" "5000" "100" "Medium Backend (500ms)"
run_comparison "1000" "5000" "100" "Slow Backend (1000ms)"
run_comparison "2000" "5000" "100" "Very Slow Backend (2000ms)"

echo ""
echo ">>> Stopping Server..."
kill $SERVER_PID 2>/dev/null || true

echo ""
echo ">>> All Stampede Tests Complete <<<"
