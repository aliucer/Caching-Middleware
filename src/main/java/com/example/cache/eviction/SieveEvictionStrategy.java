package com.example.cache.eviction;

import com.example.cache.core.CacheEntry;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantLock;

/**
 * SIEVE Eviction Strategy.
 * Based on "SIEVE is Simpler than LRU: an Efficient Turn-Key Eviction Algorithm for Web Caches" (NSDI '24).
 * 
 * Unlike LRU, SIEVE does not promote items to the head on hits (onHit is O(1) and only sets a bit).
 * It uses a "Hand" pointer that sweeps from Tail to Head looking for a victim.
 * Visited items are spared (visited set to false) and kept in place (Lazy Demotion).
 * Unvisited items are evicted.
 */
public class SieveEvictionStrategy implements EvictionStrategy {

    private static class Node {
        String key;
        boolean visited; // Accessed bit
        Node prev;
        Node next;

        Node(String key) {
            this.key = key;
            this.visited = false; // Inserted with visited=0 (Quick Demotion for scan resistance)
        }
    }

    private final ReentrantLock lock = new ReentrantLock();
    
    // Key -> Node map for O(1) access
    private final Map<String, Node> nodeMap = new HashMap<>();
    
    // Doubly Linked List Pointers
    private Node head;
    private Node tail;
    
    // The "Hand" pointer for the SIEVE algorithm
    private Node hand;

    @Override
    public void onHit(String key, CacheEntry<?> entry) {
        // SIEVE: distinct from LRU, we DO NOT move the Node on a hit.
        // We only set the visited bit. Scaling is better as this avoids lock contention on list pointers.
        lock.lock();
        try {
            Node node = nodeMap.get(key);
            if (node != null) {
                node.visited = true;
            }
        } finally {
            lock.unlock();
        }
    }

    @Override
    public void onInsert(String key, CacheEntry<?> entry) {
        lock.lock();
        try {
            // If exists (Update case)
            if (nodeMap.containsKey(key)) {
                Node node = nodeMap.get(key);
                node.visited = true;
                return;
            }

            // Create new Node
            Node newNode = new Node(key);
            nodeMap.put(key, newNode);

            // Insert at the head of the list
            addToHead(newNode);

        } finally {
            lock.unlock();
        }
    }

    @Override
    public void onMiss(String key) {
        // No-op for main logic
    }

    @Override
    public Optional<String> selectVictim(ConcurrentHashMap<String, CacheEntry<Object>> store) {
        lock.lock();
        try {
            // Hand starts at tail if null
            if (hand == null) {
                hand = tail;
            }

            // Sifting Process
            while (hand != null) {
                // If visited, give second chance: reset boolean, keep in list, move hand
                if (hand.visited) {
                    hand.visited = false;
                    // Move hand to prev (towards head). Wrap around to tail if needed (handled in loop if needed, but logic below wraps)
                    hand = (hand.prev != null) ? hand.prev : tail; 
                } else {
                    // Found victim (not visited)
                    String victimKey = hand.key;
                    Node victimNode = hand;

                    // Move hand before removing
                    hand = (hand.prev != null) ? hand.prev : tail;

                    // Remove victim from list and map
                    removeNode(victimNode);
                    nodeMap.remove(victimKey);

                    return Optional.of(victimKey);
                }
            }
            return Optional.empty(); // Should not happen unless empty
        } finally {
            lock.unlock();
        }
    }

    // --- Helper Methods (Doubly Linked List Operations) ---

    private void addToHead(Node node) {
        if (head == null) {
            head = tail = node;
        } else {
            node.next = head;
            head.prev = node;
            head = node;
        }
    }

    private void removeNode(Node node) {
        if (node.prev != null) {
            node.prev.next = node.next;
        } else {
            head = node.next; // Removing Head
        }

        if (node.next != null) {
            node.next.prev = node.prev;
        } else {
            tail = node.prev; // Removing Tail
        }
        
        // Safety check: if we are somehow deleting the hand (shouldn't happen in the loop logic above, but good for robustness)
        if (node == hand) {
            hand = (node.prev != null) ? node.prev : tail;
        }
    }
}
