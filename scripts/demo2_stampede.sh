#!/bin/bash
# =============================================================
# DEMO 2: Stampede Prevention - Naive vs Coalescing
# Shows how coalescing prevents thundering herd
# =============================================================

clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       DEMO 2: Stampede Prevention - Naive vs Coalescing      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

BASE_URL="http://localhost:8080"
CONCURRENT_REQUESTS=50

run_stampede_test() {
    local mode=$1
    local mode_name=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ Testing: $mode_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Configure: very short TTL to force expiration
    echo "⚙️  Configuring: TTL=100ms (expires quickly), latency=200ms"
    curl -s "$BASE_URL/config?mode=$mode&capacity=100&ttl=100&latency=200" > /dev/null
    curl -s "$BASE_URL/reset" > /dev/null
    sleep 0.3
    
    # First request to populate cache
    echo ""
    echo "📥 Initial request to populate cache..."
    curl -s "$BASE_URL/item?key=popular_item" > /dev/null
    
    # Wait for TTL to expire
    echo "⏳ Waiting 150ms for TTL to expire..."
    sleep 0.15
    
    # Get backend count before stampede
    STATS_BEFORE=$(curl -s "$BASE_URL/stats")
    BACKEND_BEFORE=$(echo $STATS_BEFORE | grep -o '"backendRequests":[0-9]*' | cut -d: -f2)
    
    # Simulate stampede: many concurrent requests to same expired key
    echo ""
    echo "🐘 STAMPEDE! Sending $CONCURRENT_REQUESTS concurrent requests..."
    echo "   All hitting the SAME expired key at the SAME time!"
    
    # Send concurrent requests
    for i in $(seq 1 $CONCURRENT_REQUESTS); do
        curl -s "$BASE_URL/item?key=popular_item" > /dev/null &
    done
    
    # Wait for all to complete
    wait
    
    # Get backend count after stampede
    sleep 0.3
    STATS_AFTER=$(curl -s "$BASE_URL/stats")
    BACKEND_AFTER=$(echo $STATS_AFTER | grep -o '"backendRequests":[0-9]*' | cut -d: -f2)
    
    BACKEND_CALLS=$((BACKEND_AFTER - BACKEND_BEFORE))
    
    echo ""
    echo "📈 RESULTS for $mode_name:"
    echo "   • Concurrent requests: $CONCURRENT_REQUESTS"
    echo "   • Backend calls made: $BACKEND_CALLS"
    
    if [ $BACKEND_CALLS -le 5 ]; then
        REDUCTION=$(echo "scale=1; (1 - $BACKEND_CALLS / $CONCURRENT_REQUESTS) * 100" | bc)
        echo "   ✅ Backend reduction: ~${REDUCTION}%"
        echo "   ✅ Stampede PREVENTED!"
    else
        echo "   ❌ Too many backend calls - STAMPEDE occurred!"
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
run_stampede_test "M1" "LRU + Naive (NO protection)"
sleep 1
run_stampede_test "M2" "LRU + Coalescing (WITH protection)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 CONCLUSION:"
echo "   • Naive: ALL $CONCURRENT_REQUESTS requests hit backend (stampede!)"
echo "   • Coalescing: Only 1 request hits backend, others wait"
echo "   • Coalescing uses computeIfAbsent pattern for thread safety"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

