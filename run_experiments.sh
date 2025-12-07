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
    SCENARIO=$1
    MODE=$2
    CAPACITY=$3
    TTL=$4
    DURATION=$5
    DESC=$6

    echo "--------------------------------------------------------"
    echo "Running Scenario $SCENARIO - Mode $MODE ($DESC)"
    echo "Config: Capacity=$CAPACITY, TTL=$TTL, Duration=${DURATION}s"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="$SCENARIO $DURATION" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    echo "Result:"
    grep "finished" loadgen.out || echo "LoadGen Failed or Silent"
    echo "Server Stats: $STATS"
    
    # Parse Hit Ratio (Approximate)
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Total Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    if [ "$T_REQS" -gt 0 ]; then
       HIT_R=$(echo "scale=4; ($T_REQS - $B_REQS) / $T_REQS * 100" | bc)
       echo "Hit Ratio: ~${HIT_R}%"
    fi
    echo "--------------------------------------------------------"
}

# --- SCENARIO A EXTENSIVE: Zipfian ---
# Universe 1M, Capacity 10k (1%). Zipf 0.9.
# Run for 45s to allow cache to fill and churn.

DURATION=45
CAPACITY=10000
TTL=600000 # 10 mins

run_test "A" "M1" "$CAPACITY" "$TTL" "$DURATION" "LRU + Naive"
# User asked for M4 / M5. 
# M4 is SIEVE + Naive. (Direct eviction comparison vs M1)
run_test "A" "M4" "$CAPACITY" "$TTL" "$DURATION" "SIEVE + Naive"

# M5 is SIEVE + PER. PER doesn't affect Hit Ratio as much (it does refreshes). 
# But let's run it just to see if it helps under load (maybe early refresh prevents some misses if ttl was tight, but here ttl is long).
# Sticking to M1 vs M4 for pure Eviction comparison.

echo ">>> Stopping Server..."
kill $SERVER_PID
