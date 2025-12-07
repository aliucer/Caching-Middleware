package com.example.cache.core;

import com.example.cache.eviction.EvictionStrategy;
import com.example.cache.refresh.RefreshStrategy;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

public class CacheService {

    private final ConcurrentHashMap<String, CacheEntry<Object>> store;
    private final EvictionStrategy evictionStrategy;
    private final RefreshStrategy refreshStrategy;
    private final int capacity;
    private final long ttlMillis;

    public CacheService(
        EvictionStrategy evictionStrategy,
        RefreshStrategy refreshStrategy,
        int capacity,
        long ttlMillis
    ) {
        this.store = new ConcurrentHashMap<>();
        this.evictionStrategy = evictionStrategy;
        this.refreshStrategy = refreshStrategy;
        this.capacity = capacity;
        this.ttlMillis = ttlMillis;
    }

    public Object get(String key, Supplier<Object> recomputeFn) throws Exception {
        return refreshStrategy.get(key, recomputeFn, store, evictionStrategy, capacity, ttlMillis);
    }
    
    // Helper to inspect store size for metrics if needed
    public int size() {
        return store.size();
    }
    
    // Clear cache for experiments
    public void clear() {
        store.clear();
        // NOTE: Strategy-specific metadata (queue, order) also needs clearing if we reuse the same instance?
        // Ideally we recreate the service or strategy for new experiments. 
        // For now, assume strategies are fresh or we trust them to handle empty store? 
        // LRU order/queue won't be cleared automatically if we just clear store.
        // We might need a clear() method on EvictionStrategy too, but instructions didn't specify. 
        // We will recreate the strategies in the controller when switching modes.
    }
}
