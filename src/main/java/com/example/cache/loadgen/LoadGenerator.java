package com.example.cache.loadgen;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.IntStream;
import org.apache.commons.math3.distribution.ZipfDistribution;

public class LoadGenerator {

    private static final HttpClient client = HttpClient.newHttpClient();
    private static final String BASE_URL = "http://localhost:8080";

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.out.println("Usage: java LoadGenerator <scenario> [durationSeconds]");
            return;
        }

        String scenario = args[0];
        int duration = args.length > 1 ? Integer.parseInt(args[1]) : 60;
        
        // Optional extra args for Scenario A
        // args[2]: threads
        // args[3]: universe
        // args[4]: alpha (double)
        
        System.out.println("Starting Scenario: " + scenario + " Duration: " + duration + "s");

        switch (scenario) {
            case "A":
                int threads = args.length > 2 ? Integer.parseInt(args[2]) : 50;
                int universe = args.length > 3 ? Integer.parseInt(args[3]) : 1_000_000;
                double alpha = args.length > 4 ? Double.parseDouble(args[4]) : 0.9;
                double scanRatio = args.length > 5 ? Double.parseDouble(args[5]) : 0.0;
                runScenarioA(duration, threads, universe, alpha, scanRatio);
                break;
            case "B":
                int bThreads = args.length > 2 ? Integer.parseInt(args[2]) : 100;
                runScenarioB(duration, bThreads);
                break;
            case "C":
                int cThreads = args.length > 2 ? Integer.parseInt(args[2]) : 200;
                int cTotalKeys = args.length > 3 ? Integer.parseInt(args[3]) : 100_000;
                int cHotKeys = args.length > 4 ? Integer.parseInt(args[4]) : 1_000;
                double cHotRatio = args.length > 5 ? Double.parseDouble(args[5]) : 0.8;
                runScenarioC(duration, cThreads, cTotalKeys, cHotKeys, cHotRatio);
                break;
            case "D":
                runScenarioD(duration);
                break;
            default:
                System.out.println("Unknown scenario: " + scenario);
        }
    }

    // Scenario A: Realistic Zipfian Workload (Memory-constrained) WITH SCAN SUPPORT
    private static void runScenarioA(int durationSeconds, int threads, int universeSize, double alpha, double scanRatio) throws Exception {
        // ... (Unchanged)
        // Note: For brevity in this replacing block, keeping previous implementation reference or assuming user context holds it.
        // Actually, I should better not touch Scenario A lines if I can avoid it, but the switch case is shared.
        // Re-writing Scenario A calling logic in switch is fine.
        
        // Let's implement full switch to be safe.
        // Apache Commons Math ZipfDistribution
        final ZipfDistribution zipf = new ZipfDistribution(universeSize, alpha);
        final AtomicLong scanIndex = new AtomicLong(universeSize + 10000); // Start scan keys outside universe
        
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        AtomicLong requestCount = new AtomicLong();
        long endTime = System.currentTimeMillis() + durationSeconds * 1000L;
        
        System.out.println(String.format("Initializing Zipfian Scenario A (Universe=%d, Threads=%d, Alpha=%.2f, ScanRatio=%.2f)...", universeSize, threads, alpha, scanRatio));

        for (int i = 0; i < threads; i++) {
            executor.submit(() -> {
                Random rand = new Random();
                while (System.currentTimeMillis() < endTime) {
                    String key;
                    if (rand.nextDouble() < scanRatio) {
                        key = "scan-" + scanIndex.getAndIncrement();
                    } else {
                        int rank = zipf.sample(); 
                        key = "key-" + rank; 
                    }
                    try {
                        sendGet(key);
                        requestCount.incrementAndGet();
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
            });
        }
        
        executor.shutdown();
        executor.awaitTermination(durationSeconds + 10, TimeUnit.SECONDS);
        System.out.println("Scenario A finished. Total Requests: " + requestCount.get());
    }

    // Scenario B: Thundering Herd (Sustained)
    private static void runScenarioB(int durationSeconds, int threads) throws Exception {
        // "Live Event" simulation
        // Multiple threads hammering a SINGLE key for the duration.
        // This tests what happens when TTL expires repeatedly under load.
        
        String hotKey = "hot-key-stampede";
        
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        AtomicLong requestCount = new AtomicLong();
        
        // Use synchronized list for simple stats collection (DescriptiveStatistics is not thread safe for addValue)
        // Or better, use histogram. For simplicity and since we have huge memory, a list is fine for P99.
        // Actually, let's use a ConcurrentLinkedQueue and then dump to DesciptiveStatistics at the end.
        // Or synchronized collection.
        java.util.concurrent.ConcurrentLinkedQueue<Double> latencies = new java.util.concurrent.ConcurrentLinkedQueue<>();

        long endTime = System.currentTimeMillis() + durationSeconds * 1000L;
        
        System.out.println(String.format("Initializing Scenario B (Threads=%d, Duration=%ds)...", threads, durationSeconds));

        for (int i = 0; i < threads; i++) {
            executor.submit(() -> {
                while (System.currentTimeMillis() < endTime) {
                    try {
                        long start = System.currentTimeMillis();
                        sendGet(hotKey);
                        long end = System.currentTimeMillis();
                        latencies.add((double) (end - start));
                        
                        requestCount.incrementAndGet();
                        // Small sleep to allow context switching and prevent local CPU saturation
                        // obscuring the network/backend bottleneck.
                        Thread.sleep(1); 
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
            });
        }

        executor.shutdown();
        executor.awaitTermination(durationSeconds + 10, TimeUnit.SECONDS);
        
        // Calculate Stats
        org.apache.commons.math3.stat.descriptive.DescriptiveStatistics stats = new org.apache.commons.math3.stat.descriptive.DescriptiveStatistics();
        latencies.forEach(stats::addValue);
        
        System.out.println("Scenario B finished. Requests: " + requestCount.get());
        System.out.println(String.format("Stats: P99=%.2fms, Max=%.2fms", stats.getPercentile(99), stats.getMax()));
    }

    // Scenario C: Mixed Workload (Pareto/Hot-Cold)
    private static void runScenarioC(int durationSeconds, int threads, int totalKeys, int hotKeys, double hotRatio) throws Exception {
        
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        AtomicLong requestCount = new AtomicLong();
        long endTime = System.currentTimeMillis() + durationSeconds * 1000L;
        
        System.out.println(String.format("Initializing Scenario C (Threads=%d, TotalKeys=%d, HotKeys=%d, HotRatio=%.2f)...", threads, totalKeys, hotKeys, hotRatio));

        for (int i = 0; i < threads; i++) {
            executor.submit(() -> {
                Random rand = new Random();
                while (System.currentTimeMillis() < endTime) {
                    String key;
                    if (rand.nextDouble() < hotRatio) {
                        key = "key-" + rand.nextInt(hotKeys);
                    } else {
                        key = "key-" + (hotKeys + rand.nextInt(totalKeys - hotKeys));
                    }
                    try {
                        sendGet(key);
                        requestCount.incrementAndGet();
                        // Removed Thread.sleep to maximize throughput / stress
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
            });
        }
        
        executor.shutdown();
        executor.awaitTermination(durationSeconds + 10, TimeUnit.SECONDS);
        System.out.println("Scenario C finished. Requests: " + requestCount.get());
    }

    private static void sendGet(String key) throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(BASE_URL + "/item?key=" + key))
            .GET()
            .build();
        client.send(request, HttpResponse.BodyHandlers.discarding());
    }

    // Scenario D: Scan Resistance (LRU vs SIEVE)
    private static void runScenarioD(int durationSeconds) throws Exception {
        int threads = 50; 
        int hotKeys = 200;
        
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        AtomicLong requestCount = new AtomicLong();
        long endTime = System.currentTimeMillis() + durationSeconds * 1000L;
        
        AtomicLong scanIndex = new AtomicLong(10000); // Start scan keys at 10000
        
        for (int i = 0; i < threads; i++) {
            executor.submit(() -> {
                Random rand = new Random();
                while (System.currentTimeMillis() < endTime) {
                    String key;
                    if (rand.nextDouble() < 0.9) {
                        // Hot key access
                        key = "hot-" + rand.nextInt(hotKeys);
                    } else {
                        // Scan access (unique)
                        key = "scan-" + scanIndex.getAndIncrement();
                    }
                    try {
                        sendGet(key);
                        requestCount.incrementAndGet();
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
            });
        }
        
        executor.shutdown();
        executor.awaitTermination(durationSeconds + 10, TimeUnit.SECONDS);
        System.out.println("Scenario D finished. Requests: " + requestCount.get());
    }

    // Scenario E: Comprehensive Multi-Phase Realistic Workload
    // Usage: E <totalKeys> <hotKeys> <hotRatio> <phaseDurations> <phaseThreads>
    // Example: E 100000 1000 0.8 120,240,120,240 50,200,500,200
    public static void runScenarioE(int totalKeys, int hotKeys, double hotRatio, 
                                     int[] phaseDurations, int[] phaseThreads) throws Exception {
        
        System.out.println("=== SCENARIO E: Multi-Phase Realistic Workload ===");
        System.out.println(String.format("Keys: Total=%d, Hot=%d, HotRatio=%.2f", totalKeys, hotKeys, hotRatio));
        System.out.println("Phases: " + phaseDurations.length);
        
        java.util.concurrent.ConcurrentLinkedQueue<Double> allLatencies = new java.util.concurrent.ConcurrentLinkedQueue<>();
        AtomicLong totalRequests = new AtomicLong();
        
        for (int phase = 0; phase < phaseDurations.length; phase++) {
            int durationSec = phaseDurations[phase];
            int threads = phaseThreads[phase];
            
            System.out.println(String.format("\n--- Phase %d: Duration=%ds, Threads=%d ---", phase + 1, durationSec, threads));
            
            java.util.concurrent.ConcurrentLinkedQueue<Double> phaseLatencies = new java.util.concurrent.ConcurrentLinkedQueue<>();
            AtomicLong phaseRequests = new AtomicLong();
            
            ExecutorService executor = Executors.newFixedThreadPool(threads);
            long endTime = System.currentTimeMillis() + durationSec * 1000L;
            
            for (int i = 0; i < threads; i++) {
                executor.submit(() -> {
                    Random rand = new Random();
                    while (System.currentTimeMillis() < endTime) {
                        String key;
                        if (rand.nextDouble() < hotRatio) {
                            key = "key-" + rand.nextInt(hotKeys);
                        } else {
                            key = "key-" + (hotKeys + rand.nextInt(totalKeys - hotKeys));
                        }
                        try {
                            long start = System.currentTimeMillis();
                            sendGet(key);
                            long latency = System.currentTimeMillis() - start;
                            phaseLatencies.add((double) latency);
                            allLatencies.add((double) latency);
                            phaseRequests.incrementAndGet();
                            totalRequests.incrementAndGet();
                        } catch (Exception e) {
                            // Ignore connection errors under heavy load
                        }
                    }
                });
            }
            
            executor.shutdown();
            executor.awaitTermination(durationSec + 30, TimeUnit.SECONDS);
            
            // Calculate Phase Stats
            org.apache.commons.math3.stat.descriptive.DescriptiveStatistics stats = 
                new org.apache.commons.math3.stat.descriptive.DescriptiveStatistics();
            phaseLatencies.forEach(stats::addValue);
            
            double rps = phaseRequests.get() / (double) durationSec;
            System.out.println(String.format("Phase %d Results: Requests=%d, RPS=%.1f, Avg=%.2fms, P95=%.2fms, P99=%.2fms, Max=%.2fms",
                phase + 1, phaseRequests.get(), rps, stats.getMean(), stats.getPercentile(95), stats.getPercentile(99), stats.getMax()));
        }
        
        // Calculate Overall Stats
        org.apache.commons.math3.stat.descriptive.DescriptiveStatistics overallStats = 
            new org.apache.commons.math3.stat.descriptive.DescriptiveStatistics();
        allLatencies.forEach(overallStats::addValue);
        
        System.out.println("\n=== OVERALL RESULTS ===");
        System.out.println(String.format("Total Requests: %d", totalRequests.get()));
        System.out.println(String.format("Overall Avg=%.2fms, P95=%.2fms, P99=%.2fms, Max=%.2fms",
            overallStats.getMean(), overallStats.getPercentile(95), overallStats.getPercentile(99), overallStats.getMax()));
    }
}

