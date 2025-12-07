package com.example.cache.refresh;

import com.example.cache.core.CacheEntry;
import com.example.cache.eviction.EvictionStrategy;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

public interface RefreshStrategy {
    Object get(
        String key,
        Supplier<Object> recomputeFn,
        ConcurrentHashMap<String, CacheEntry<Object>> store,
        EvictionStrategy evictionStrategy,
        int capacity,
        long ttlMillis
    ) throws Exception;
}
