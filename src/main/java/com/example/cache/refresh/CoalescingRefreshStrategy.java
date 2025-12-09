package com.example.cache.refresh;

import com.example.cache.core.CacheEntry;
import com.example.cache.eviction.EvictionStrategy;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.function.Supplier;

public class CoalescingRefreshStrategy implements RefreshStrategy {

    private final ConcurrentHashMap<String, CompletableFuture<Object>> inFlight = new ConcurrentHashMap<>();

    // Dedicated thread pool to avoid ForkJoinPool exhaustion under high load
    private final java.util.concurrent.ExecutorService asyncExecutor = java.util.concurrent.Executors
            .newFixedThreadPool(200);

    @Override
    public Object get(
            String key,
            Supplier<Object> recomputeFn,
            ConcurrentHashMap<String, CacheEntry<Object>> store,
            EvictionStrategy evictionStrategy,
            int capacity,
            long ttlMillis) throws Exception {

        long now = System.currentTimeMillis();
        CacheEntry<Object> entry = store.get(key);

        if (entry != null && entry.expiryTime > now) {
            evictionStrategy.onHit(key, entry);
            return entry.value;
        }

        evictionStrategy.onMiss(key);

        CompletableFuture<Object> future = inFlight.computeIfAbsent(key, k ->
        // Pass the custom executor here
        CompletableFuture.supplyAsync(() -> {
            long start = System.nanoTime();
            Object value = recomputeFn.get();
            long delta = System.nanoTime() - start;

            CacheEntry<Object> newEntry = new CacheEntry<>(value, System.currentTimeMillis() + ttlMillis, delta);

            if (store.size() >= capacity) {
                evictionStrategy
                        .selectVictim(store)
                        .ifPresent(victimKey -> store.remove(victimKey));
            }

            store.put(key, newEntry);
            evictionStrategy.onInsert(key, newEntry);

            return value;
        }, asyncExecutor));

        try {
            return future.get();
        } finally {
            inFlight.remove(key, future);
        }
    }
}
