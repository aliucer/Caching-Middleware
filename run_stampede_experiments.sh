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

echo ">>> Starting Server..."
# Using high heap to support 1000 threads if needed
java -Xmx1G -jar target/caching-middleware-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for start
sleep 10

run_test() {
    MODE=$1
    LATENCY=$2
    TTL=$3
    THREADS=$4
    DESC=$5

    # Shorter duration but enough to see repetitive cycles
    DURATION=20
    # Capacity is irrelevant for Scenario B (single key), but keep it small
    CAPACITY=100
    
    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Lat: ${LATENCY}ms | TTL: ${TTL}ms | Threads: $THREADS"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen: B <duration> <threads>
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="B $DURATION $THREADS" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse Backend Requests
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    # Parse Latency Stats
    P99=$(grep -o 'P99=[0-9.]*' loadgen.out | cut -d= -f2 | sed 's/ms//')
    MAX=$(grep -o 'Max=[0-9.]*' loadgen.out | cut -d= -f2 | sed 's/ms//')
    
    # Calculate Backend Load Ratio (Backend / Total)
    # Lower is better. Ideally near (Duration / TTL)
    
    LOAD_RATIO="0"
    if [ "$T_REQS" -gt 0 ]; then
       LOAD_RATIO=$(echo "scale=4; $B_REQS / $T_REQS * 100" | bc)
    fi
     
    echo "Result: Total=$T_REQS, Backend=$B_REQS, Load=${LOAD_RATIO}%, P99=${P99}ms, Max=${MAX}ms"
    echo "--------------------------------------------------------"
}

run_comparison() {
    LAT=$1
    TTL=$2
    TH=$3
    NAME=$4
    
    echo "=== CASE: $NAME ==="
    # M1: Naive (Control)
    run_test "M1" "$LAT" "$TTL" "$TH" "Naive"
    
    # M2: Coalescing (The Solution)
    run_test "M2" "$LAT" "$TTL" "$TH" "Coalescing"
    
    # M3: PER (The Optimization)
    run_test "M3" "$LAT" "$TTL" "$TH" "PER"
    echo ""
}

# --- STAMPEDE MATRIX ---

# Case 1: Standard Stampede
# 100 Threads, Latency 100ms, TTL 1000ms.
# 100 threads hitting every ms. 
# Naive: Every 1s, 100 threads race. Should see ~100 backend calls per second? 
# Coalescing: Should see 1 backend call per second.
run_comparison "100" "1000" "100" "Standard Stampede"

# Case 2: Massive Concurrency (Thundering Herd)
# 1000 Threads, Latency 200ms, TTL 2000ms.
# Huge gap. 1000 threads waiting.
run_comparison "200" "2000" "1000" "Massive Concurrency"

# Case 3: Death Spiral (Latency > TTL)
# Latency 500ms, TTL 200ms.
# By the time data arrives, it's almost expired (or logic handles it).
# But threads keep piling up.
run_comparison "500" "200" "200" "Death Spiral"


echo ">>> Stopping Server..."
kill $SERVER_PID
