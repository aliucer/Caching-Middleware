package com.example.cache.refresh;

import com.example.cache.core.CacheEntry;
import com.example.cache.eviction.EvictionStrategy;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

public class NaiveTtlRefreshStrategy implements RefreshStrategy {

    @Override
    public Object get(
        String key,
        Supplier<Object> recomputeFn,
        ConcurrentHashMap<String, CacheEntry<Object>> store,
        EvictionStrategy evictionStrategy,
        int capacity,
        long ttlMillis
    ) throws Exception {

        long now = System.currentTimeMillis();
        CacheEntry<Object> entry = store.get(key);

        if (entry != null && entry.expiryTime > now) {
            evictionStrategy.onHit(key, entry);
            return entry.value;
        }

        evictionStrategy.onMiss(key);

        long start = System.nanoTime();
        Object value = recomputeFn.get();
        long delta = System.nanoTime() - start;

        CacheEntry<Object> newEntry = new CacheEntry<>(value, now + ttlMillis, delta);

        if (store.size() >= capacity) {
            evictionStrategy
                .selectVictim(store)
                .ifPresent(victimKey -> store.remove(victimKey));
        }

        store.put(key, newEntry);
        evictionStrategy.onInsert(key, newEntry);

        return value;
    }
}
