package com.example.cache.eviction;

import com.example.cache.core.CacheEntry;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

public interface EvictionStrategy {
    void onHit(String key, CacheEntry<?> entry);
    void onMiss(String key);
    void onInsert(String key, CacheEntry<?> entry);
    Optional<String> selectVictim(ConcurrentHashMap<String, CacheEntry<Object>> store);
}
