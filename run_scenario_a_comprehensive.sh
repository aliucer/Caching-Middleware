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

# Fixed params
DURATION=30
TTL=600000   # 10 min TTL (effectively permanent for this test)

run_test() {
    MODE=$1
    CAPACITY=$2
    UNIVERSE=$3
    ALPHA=$4
    LATENCY=$5
    THREADS=$6
    SCAN_RATIO=$7
    DESC=$8

    echo "--------------------------------------------------------"
    echo "Test: $DESC"
    echo "Mode: $MODE | Cap: $CAPACITY | Univ: $UNIVERSE | Alpha: $ALPHA | Scan: $SCAN_RATIO | Lat: ${LATENCY}ms"
    
    # Configure
    curl -s "http://localhost:8080/config?mode=$MODE&capacity=$CAPACITY&ttl=$TTL&latency=$LATENCY" > /dev/null
    curl -s "http://localhost:8080/reset" > /dev/null
    
    # Run LoadGen
    mvn exec:java -Dexec.mainClass="com.example.cache.loadgen.LoadGenerator" -Dexec.args="A $DURATION $THREADS $UNIVERSE $ALPHA $SCAN_RATIO" -q > loadgen.out 2>&1
    
    # Capture Stats
    STATS=$(curl -s "http://localhost:8080/stats")
    
    # Parse
    B_REQS=$(echo $STATS | grep -o 'backendRequests":[0-9]*' | grep -o '[0-9]*')
    T_REQS=$(grep -o 'Total Requests: [0-9]*' loadgen.out | grep -o '[0-9]*' || echo "0")
    
    HIT_R="0"
    RPS="0"
    if [ "$T_REQS" -gt 0 ]; then
       HIT_R=$(echo "scale=2; ($T_REQS - $B_REQS) / $T_REQS * 100" | bc)
       RPS=$(echo "scale=1; $T_REQS / $DURATION" | bc)
    fi
    echo "Result: RPS=$RPS, Total=$T_REQS, Backend=$B_REQS, HitRatio=${HIT_R}%"
    echo "--------------------------------------------------------"
}

run_comparison() {
    CAP=$1
    UNIV=$2
    ALPHA=$3
    SCAN=$4
    LAT=$5
    TH=$6
    NAME=$7
    
    echo ""
    echo "============================================================"
    echo "=== CASE: $NAME ==="
    echo "=== Cap=$CAP, Univ=$UNIV, Alpha=$ALPHA, Scan=$SCAN ==="
    echo "============================================================"
    
    # M0: NoCache
    run_test "M0" "$CAP" "$UNIV" "$ALPHA" "$LAT" "$TH" "$SCAN" "NoCache"
    
    # M1: LRU + Naive
    run_test "M1" "$CAP" "$UNIV" "$ALPHA" "$LAT" "$TH" "$SCAN" "LRU"
    
    # M4: SIEVE + Naive
    run_test "M4" "$CAP" "$UNIV" "$ALPHA" "$LAT" "$TH" "$SCAN" "SIEVE"
}

echo "=========================================="
echo "=== SCENARIO A: COMPREHENSIVE EVICTION ==="
echo "=========================================="
echo "Duration: ${DURATION}s per test"
echo ""

# Standard config
LAT=10
TH=200
UNIV=100000
CAP=1000

# =============================================================================
# SECTION 1: SCAN RATIO VARIATION (Core LRU vs SIEVE comparison)
# =============================================================================
echo ""
echo "########## SECTION 1: SCAN RATIO VARIATION ##########"
echo "Fixed: Cap=1000 (1%), Univ=100k, Alpha=0.9, Threads=200, Latency=10ms"
echo ""

run_comparison "$CAP" "$UNIV" "0.9" "0.0" "$LAT" "$TH" "No Scan (Baseline)"
run_comparison "$CAP" "$UNIV" "0.9" "0.1" "$LAT" "$TH" "Light Scan (10%)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Medium Scan (25%)"
run_comparison "$CAP" "$UNIV" "0.9" "0.50" "$LAT" "$TH" "Heavy Scan (50%)"
run_comparison "$CAP" "$UNIV" "0.9" "0.75" "$LAT" "$TH" "Extreme Scan (75%)"

# =============================================================================
# SECTION 2: CACHE SIZE VARIATION
# =============================================================================
echo ""
echo "########## SECTION 2: CACHE SIZE VARIATION ##########"
echo "Fixed: Univ=100k, Alpha=0.9, Scan=25%, Threads=200"
echo ""

run_comparison "500" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Tiny Cache (0.5%)"
run_comparison "1000" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Small Cache (1%)"
run_comparison "2000" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Medium Cache (2%)"
run_comparison "5000" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Large Cache (5%)"
run_comparison "10000" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Huge Cache (10%)"

# =============================================================================
# SECTION 3: SKEW VARIATION (Alpha parameter)
# =============================================================================
echo ""
echo "########## SECTION 3: SKEW VARIATION (Alpha) ##########"
echo "Fixed: Cap=1000, Univ=100k, Scan=25%, Threads=200"
echo ""

run_comparison "$CAP" "$UNIV" "0.7" "0.25" "$LAT" "$TH" "Low Skew (Alpha=0.7)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "$TH" "Normal Skew (Alpha=0.9)"
run_comparison "$CAP" "$UNIV" "1.1" "0.25" "$LAT" "$TH" "High Skew (Alpha=1.1)"
run_comparison "$CAP" "$UNIV" "1.3" "0.25" "$LAT" "$TH" "Extreme Skew (Alpha=1.3)"

# =============================================================================
# SECTION 4: BACKEND LATENCY IMPACT
# =============================================================================
echo ""
echo "########## SECTION 4: BACKEND LATENCY IMPACT ##########"
echo "Fixed: Cap=1000, Univ=100k, Alpha=0.9, Scan=25%, Threads=200"
echo ""

run_comparison "$CAP" "$UNIV" "0.9" "0.25" "1" "$TH" "Very Fast Backend (1ms)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "10" "$TH" "Fast Backend (10ms)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "50" "$TH" "Medium Backend (50ms)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "100" "$TH" "Slow Backend (100ms)"

# =============================================================================
# SECTION 5: THREAD SCALING
# =============================================================================
echo ""
echo "########## SECTION 5: THREAD SCALING ##########"
echo "Fixed: Cap=1000, Univ=100k, Alpha=0.9, Scan=25%, Latency=10ms"
echo ""

run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "50" "Low Threads (50)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "100" "Medium Threads (100)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "200" "High Threads (200)"
run_comparison "$CAP" "$UNIV" "0.9" "0.25" "$LAT" "500" "Very High Threads (500)"

echo ""
echo ">>> Stopping Server..."
kill $SERVER_PID 2>/dev/null || true

echo ""
echo ">>> All Scenario A Tests Complete <<<"
