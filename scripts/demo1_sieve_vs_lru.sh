#!/bin/bash
# =============================================================
# DEMO 1: LRU vs SIEVE Hit Ratio Comparison
# Shows how SIEVE handles scan/one-hit-wonder traffic better
# =============================================================

clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       DEMO 1: LRU vs SIEVE - Scan Resistance                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

BASE_URL="http://localhost:8080"

# Function to warm up cache and simulate scans
run_test() {
    local mode=$1
    local mode_name=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Testing: $mode_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Configure mode: small cache (10 items), short TTL
    echo "⚙️  Configuring: capacity=10, TTL=30s, latency=50ms"
    curl -s "$BASE_URL/config?mode=$mode&capacity=10&ttl=30000&latency=50" > /dev/null
    curl -s "$BASE_URL/reset" > /dev/null
    sleep 0.5
    
    # Phase 1: Access HOT keys (these should stay in cache)
    echo ""
    echo "🔥 Phase 1: Accessing 5 HOT keys (10 times each)..."
    for i in {1..10}; do
        for key in hot1 hot2 hot3 hot4 hot5; do
            curl -s "$BASE_URL/item?key=$key" > /dev/null
        done
    done
    echo "   ✓ 50 requests to hot keys"
    
    # Phase 2: SCAN - access 10 unique keys once (one-hit-wonders)
    # With capacity=10 and 5 hot keys, adding 10 scan keys means 5 evictions
    # SIEVE will evict scan keys (v=0), LRU will evict hot keys (oldest)
    echo ""
    echo "🔍 Phase 2: SCAN - 10 unique keys accessed ONCE (one-hit-wonders)..."
    for i in {1..10}; do
        curl -s "$BASE_URL/item?key=scan_$i" > /dev/null
    done
    echo "   ✓ 10 scan requests"
    
    # Phase 3: Access HOT keys again - will they still be in cache?
    echo ""
    echo "🔥 Phase 3: Re-accessing HOT keys... (will they be in cache?)"
    
    STATS_BEFORE=$(curl -s "$BASE_URL/stats")
    BACKEND_BEFORE=$(echo $STATS_BEFORE | grep -o '"backendRequests":[0-9]*' | cut -d: -f2)
    
    for key in hot1 hot2 hot3 hot4 hot5; do
        curl -s "$BASE_URL/item?key=$key" > /dev/null
    done
    
    STATS_AFTER=$(curl -s "$BASE_URL/stats")
    BACKEND_AFTER=$(echo $STATS_AFTER | grep -o '"backendRequests":[0-9]*' | cut -d: -f2)
    
    BACKEND_DIFF=$((BACKEND_AFTER - BACKEND_BEFORE))
    HITS=$((5 - BACKEND_DIFF))
    
    echo ""
    echo "📈 RESULTS for $mode_name:"
    echo "   • Hot key re-accesses: 5"
    echo "   • Cache HITS: $HITS / 5"
    echo "   • Cache MISSES (backend calls): $BACKEND_DIFF"
    
    if [ $HITS -ge 4 ]; then
        echo "   ✅ Hot keys survived the scan!"
    else
        echo "   ❌ Hot keys were evicted by scan traffic!"
    fi
    echo ""
}

# Check if server is running
echo "🔍 Checking if server is running..."
if ! curl -s "$BASE_URL/stats" > /dev/null 2>&1; then
    echo "❌ Server not running! Start it with:"
    echo "   cd /home/ali/cmpe273/caching-middleware"
    echo "   ./mvnw spring-boot:run"
    exit 1
fi
echo "✅ Server is running!"
echo ""

# Run tests
run_test "M1" "LRU + Naive"
sleep 1
run_test "M4" "SIEVE + Naive"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 CONCLUSION:"
echo "   • SIEVE protects hot keys from scan pollution"
echo "   • LRU treats all accesses equally → hot keys get evicted"
echo "   • SIEVE's 'visited bit' gives second chances to popular items"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
