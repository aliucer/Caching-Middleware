package com.example.cache.eviction;

import com.example.cache.core.CacheEntry;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantLock;

public class LruEvictionStrategy implements EvictionStrategy {

    private final ReentrantLock lock = new ReentrantLock();

    // LinkedHashMap in access-order mode: accessOrder = true
    private final LinkedHashMap<String, Boolean> order =
        new LinkedHashMap<>(16, 0.75f, true);

    @Override
    public void onHit(String key, CacheEntry<?> entry) {
        lock.lock();
        try {
            // access-order LinkedHashMap moves key to end on get/put
            if (order.containsKey(key)) {
                order.get(key); // touch it to update recency
            }
        } finally {
            lock.unlock();
        }
    }

    @Override
    public void onInsert(String key, CacheEntry<?> entry) {
        lock.lock();
        try {
            order.put(key, Boolean.TRUE);
        } finally {
            lock.unlock();
        }
    }

    @Override
    public void onMiss(String key) {
        // no-op
    }

    @Override
    public Optional<String> selectVictim(ConcurrentHashMap<String, CacheEntry<Object>> store) {
        lock.lock();
        try {
            Iterator<Map.Entry<String, Boolean>> it = order.entrySet().iterator();
            while (it.hasNext()) {
                Map.Entry<String, Boolean> e = it.next();
                String candidateKey = e.getKey();
                // candidate may already be removed from store
                if (!store.containsKey(candidateKey)) {
                    it.remove();
                    continue;
                }
                it.remove(); // remove from order
                return Optional.of(candidateKey);
            }
            return Optional.empty();
        } finally {
            lock.unlock();
        }
    }
}
