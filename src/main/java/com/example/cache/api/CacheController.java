package com.example.cache.api;

import com.example.cache.backend.MockBackend;
import com.example.cache.core.CacheService;
import com.example.cache.eviction.LruEvictionStrategy;
import com.example.cache.eviction.SieveEvictionStrategy;
import com.example.cache.refresh.CoalescingRefreshStrategy;
import com.example.cache.refresh.NaiveTtlRefreshStrategy;
import com.example.cache.refresh.ProbabilisticEarlyRefreshStrategy;
import com.example.cache.refresh.RefreshStrategy;
import com.example.cache.eviction.EvictionStrategy;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import jakarta.annotation.PostConstruct;

@RestController
public class CacheController {

    private final MockBackend backend;
    private CacheService cacheService;
    
    // Default configs
    private int capacity = 10_000;
    private long ttlMillis = 60_000;
    
    // Current Mode
    private String currentMode = "M1"; 

    public CacheController(MockBackend backend) {
        this.backend = backend;
    }

    @PostConstruct
    public void init() {
        // Initialize default (M1: LRU + Naive)
        switchMode("M1", capacity, ttlMillis);
    }

    @GetMapping("/item")
    public Object getItem(@RequestParam String key) throws Exception {
        if ("M0".equals(currentMode)) {
            return backend.fetchFromBackend(key);
        }
        return cacheService.get(key, () -> backend.fetchFromBackend(key));
    }
    
    @GetMapping("/config")
    public String configure(
        @RequestParam String mode, 
        @RequestParam(defaultValue = "10000") int capacity,
        @RequestParam(defaultValue = "60000") long ttl,
        @RequestParam(defaultValue = "500") long latency
    ) {
        backend.setLatencyMillis(latency);
        switchMode(mode, capacity, ttl);
        return "Switched to " + mode + " with capacity=" + capacity + ", ttl=" + ttl + ", latency=" + latency;
    }


    @GetMapping("/stats")
    public java.util.Map<String, Object> getStats() {
        return java.util.Map.of(
            "backendRequests", backend.getRequestCount(),
            "cacheSize", cacheService != null ? cacheService.size() : 0
        );
    }

    @GetMapping("/reset")
    public void reset() {
        backend.resetCount();
        if (cacheService != null) {
            cacheService.clear();
        }
    }

    private synchronized void switchMode(String mode, int cap, long ttl) {
        this.currentMode = mode;
        this.capacity = cap;
        this.ttlMillis = ttl;

        EvictionStrategy eviction = null;
        RefreshStrategy refresh = null;

        switch (mode) {
            case "M0":
                // No cache, handled in getItem
                return;
            case "M1":
                eviction = new LruEvictionStrategy();
                refresh = new NaiveTtlRefreshStrategy();
                break;
            case "M2":
                eviction = new LruEvictionStrategy();
                refresh = new CoalescingRefreshStrategy();
                break;
            case "M3":
                eviction = new LruEvictionStrategy();
                refresh = new ProbabilisticEarlyRefreshStrategy();
                break;
            case "M4":
                eviction = new SieveEvictionStrategy();
                refresh = new NaiveTtlRefreshStrategy();
                break;
            case "M5":
                eviction = new SieveEvictionStrategy();
                refresh = new ProbabilisticEarlyRefreshStrategy();
                break;
            default:
                throw new IllegalArgumentException("Unknown mode: " + mode);
        }
        
        this.cacheService = new CacheService(eviction, refresh, cap, ttl);
    }
}
