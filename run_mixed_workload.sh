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
java -Xmx1G -jar target/caching-middleware-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for start
sleep 10

run_test() {
    MODE=$1
    CAPACITY=$2
    LATRENCY=$3
    THREADS=$4
    TOTAL_KEYS=$5
    HOT_KEYS=$6
    HOT_RATIO=$7
    DESC=$8
    
    DURATION=30
    TTL=600000

    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Cap: $CAPACITY | Univ: $TOTAL_KEYS | Hot: $HOT_KEYS | Ratio: $HOT_RATIO"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen: C <duration> <threads> <totalKeys> <hotKeys> <hotRatio>
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="C $DURATION $THREADS $TOTAL_KEYS $HOT_KEYS $HOT_RATIO" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse Hit Ratio
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    HIT_R="0"
    if [ "$T_REQS" -gt 0 ]; then
       HIT_R=$(echo "scale=4; ($T_REQS - $B_REQS) / $T_REQS * 100" | bc)
    fi
    echo "Result: Total=$T_REQS, Backend=$B_REQS, HitRatio=${HIT_R}%"
    echo "--------------------------------------------------------"
}

run_comparison() {
    CAP=$1
    TH=$2
    TOT=$3
    HOT=$4
    RATIO=$5
    NAME=$6
    
    LAT=10 # Fast backend for high throughput

    echo "=== VARIATION: $NAME ==="
    run_test "M1" "$CAP" "$LAT" "$TH" "$TOT" "$HOT" "$RATIO" "LRU"
    run_test "M4" "$CAP" "$LAT" "$TH" "$TOT" "$HOT" "$RATIO" "SIEVE"
    echo ""
}

# --- MIXED WORKLOAD MATRIX ---

# 1. Standard Pareto (80/20 Rule)
# 80% of traffic hits 20% of keys.
# Universe: 100k. Hot Keys: 20k. Hot Ratio: 0.8
# Cache Size: 1k (1% of Universe). This is SMALL.
run_comparison "1000" "200" "100000" "20000" "0.8" "Standard Pareto (80/20)"

# 2. Hyper-Skewed (99/1 Rule) - "Celebrity Effect"
# 99% of traffic hits 1% of keys.
# Universe: 100k. Hot Keys: 1k. Hot Ratio: 0.99
# Cache Size: 1k (Fits exactly the hot set!).
# Hit ratio should be near 99% for both, but scan cleaning might matter.
run_comparison "1000" "200" "100000" "1000" "0.99" "Hyper-Skewed (99/1)"

# 3. Sparse / Uniform-ish (50/50)
# 50% of traffic hits 50% of keys.
# Universe: 100k. Hot Keys: 50k. Hot Ratio: 0.5.
# This means traffic is very spread out. The working set is HUGE (50k).
# Cache (1k) is way too small. Thrashing expected.
# Does SIEVE or LRU handle thrashing better?
run_comparison "1000" "200" "100000" "50000" "0.5" "Sparse / Uniform (50/50)"


echo ">>> Stopping Server..."
kill $SERVER_PID
