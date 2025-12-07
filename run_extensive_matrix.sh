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
java -jar target/caching-middleware-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for start
sleep 10

run_test() {
    MODE=$1
    CAPACITY=$2
    UNIVERSE=$3
    ALPHA=$4
    LATENCY=$5
    THREADS=$6
    SCAN_RATIO=$7
    DESC=$8
    
    # Optimized for High Throughput (Significant results in 30s)
    DURATION=30
    TTL=600000

    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Cap: $CAPACITY | Univ: $UNIVERSE | Alpha: $ALPHA | Scan: $SCAN_RATIO | Lat: ${LATENCY}ms"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen with args: A <duration> <threads> <universe> <alpha> <scanRatio>
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="A $DURATION $THREADS $UNIVERSE $ALPHA $SCAN_RATIO" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse Hit Ratio
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Total Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    HIT_R="0"
    if [ "$T_REQS" -gt 0 ]; then
       HIT_R=$(echo "scale=4; ($T_REQS - $B_REQS) / $T_REQS * 100" | bc)
    fi
    echo "Result: Total=$T_REQS, Backend=$B_REQS, HitRatio=${HIT_R}%"
    echo "--------------------------------------------------------"
}

run_comparison() {
    CAP=$1
    UNIV=$2
    ALPHA=$3
    SCAN=$4
    NAME=$5
    
    # High Throughput Settings
    LAT=10
    TH=200

    echo "=== VARIATION: $NAME ==="
    run_test "M1" "$CAP" "$UNIV" "$ALPHA" "$LAT" "$TH" "$SCAN" "LRU"
    run_test "M4" "$CAP" "$UNIV" "$ALPHA" "$LAT" "$TH" "$SCAN" "SIEVE"
    echo ""
}

# --- EXPERIMENT MATRIX ---

# 1. Baseline: 1% Cache, Alpha 0.9, Scan 0%
run_comparison "1000" "100000" "0.9" "0.0" "Baseline (No Scan)"

# 2. Scan Attack: 1% Cache, Alpha 0.9, Scan 25%
# 25% of traffic is junk. LRU should pollute. SIEVE should filter.
run_comparison "1000" "100000" "0.9" "0.25" "Scan Attack (25% Junk)"

# 3. High Scan: 50% Junk
run_comparison "1000" "100000" "0.9" "0.50" "Heavy Scan (50% Junk)"



echo ">>> Stopping Server..."
kill $SERVER_PID
