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
    DESC=$7
    
    # 45s duration to get massive volume
    DURATION=45
    TTL=600000

    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Cap: $CAPACITY | Univ: $UNIVERSE | Alpha: $ALPHA | Latency: ${LATENCY}ms | Threads: $THREADS"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="A $DURATION $THREADS $UNIVERSE $ALPHA" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse Hit Ratio
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Total Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    HIT_R="0"
    if [ "$T_REQS" -gt 0 ]; then
       HIT_R=$(echo "scale=4; ($T_REQS - $B_REQS) / $T_REQS * 100" | bc)
    fi
     
    RPS=$(echo "$T_REQS / $DURATION" | bc)
    
    echo "Result: TotalRequests=$T_REQS, RPS=~$RPS, HitRatio=${HIT_R}%"
    echo "--------------------------------------------------------"
}

# --- HIGH THROUGHPUT EXPERIMENT ---
# Reduced latency to 10ms (vs 500ms).
# Increased threads to 200.
# Expecting RPS > 5000.

# 1. Standard Web (Alpha 0.9) - LRU
run_test "M1" "1000" "100000" "0.9" "10" "200" "LRU High-TP"

# 2. Standard Web (Alpha 0.9) - SIEVE
run_test "M4" "1000" "100000" "0.9" "10" "200" "SIEVE High-TP"


echo ">>> Stopping Server..."
kill $SERVER_PID
