package com.example.cache.core;

public class CacheEntry<V> {
    public V value;
    public long expiryTime;   // absolute timestamp in millis when TTL expires
    public long delta;        // backend computation time (nanos or millis), used by PER
    public volatile boolean visited; // used by SIEVE; defaults to false on insert

    public CacheEntry() {
    }

    public CacheEntry(V value, long expiryTime, long delta) {
        this.value = value;
        this.expiryTime = expiryTime;
        this.delta = delta;
        this.visited = false;
    }
}
