package com.example.cache.refresh;

import com.example.cache.core.CacheEntry;
import com.example.cache.eviction.EvictionStrategy;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Supplier;

public class ProbabilisticEarlyRefreshStrategy implements RefreshStrategy {

    // Use a fixed thread pool to prevent unbounded thread growth
    private final ExecutorService asyncExecutor = Executors.newFixedThreadPool(200);
    private final double beta = 1.0; 

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

            // PER Logic Validation
            // entry.delta is in Nanoseconds (computation time).
            // We need Milliseconds for the gap formula relative to expiryTime (Millis).
            double deltaMillis = entry.delta / 1_000_000.0;
            
            // Gap is the time *before* expiry when we should start refreshing.
            // gap = delta * beta * log(rand)
            // Note: log(0..1) is negative, so -1 * ... makes it positive.
            double U = Math.random();
            double gapMillis = -1.0 * deltaMillis * beta * Math.log(U);

            // If remaining time (expiry - now) is less than gap, refresh early.
            // Equivalent to: now + gap >= expiry
            if (now + gapMillis >= entry.expiryTime) {
                // Trigger early refresh
                asyncExecutor.submit(() -> {
                    try {
                        long start = System.nanoTime();
                        Object newVal = recomputeFn.get();
                        long newDelta = System.nanoTime() - start;

                        CacheEntry<Object> newEntry = new CacheEntry<>(newVal, System.currentTimeMillis() + ttlMillis, newDelta);

                        if (store.size() >= capacity) {
                            evictionStrategy
                                .selectVictim(store)
                                .ifPresent(victimKey -> store.remove(victimKey));
                        }

                        store.put(key, newEntry);
                        evictionStrategy.onInsert(key, newEntry);
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                });
            }
            return entry.value;
        }

        // Miss or expired: fallback to naive logic (synchronous refresh)
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
