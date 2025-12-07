package com.example.cache.backend;

import org.springframework.stereotype.Component;

@Component
public class MockBackend {

    private final java.util.concurrent.atomic.AtomicLong requestCount = new java.util.concurrent.atomic.AtomicLong();
    private volatile long latencyMillis = 500;

    // Simulates a slow backend fetch
    public Object fetchFromBackend(String key) {
        requestCount.incrementAndGet();
        try {
            if (latencyMillis > 0) {
                Thread.sleep(latencyMillis); 
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return "value-for-" + key;
    }

    public void setLatencyMillis(long ms) {
        this.latencyMillis = ms;
    }

    public long getRequestCount() {
        return requestCount.get();
    }
    
    public void resetCount() {
        requestCount.set(0);
    }
}
