package com.example.cache.loadgen;

/**
 * Standalone runner for Scenario E (Multi-Phase Realistic Workload)
 * Usage: java ScenarioERunner <totalKeys> <hotKeys> <hotRatio> <phaseDurations> <phaseThreads>
 * Example: java ScenarioERunner 100000 1000 0.8 "60,120,60,120" "50,200,500,200"
 */
public class ScenarioERunner {
    
    public static void main(String[] args) throws Exception {
        if (args.length < 5) {
            System.out.println("Usage: ScenarioERunner <totalKeys> <hotKeys> <hotRatio> <phaseDurations> <phaseThreads>");
            System.out.println("Example: ScenarioERunner 100000 1000 0.8 60,120,60,120 50,200,500,200");
            return;
        }
        
        int totalKeys = Integer.parseInt(args[0]);
        int hotKeys = Integer.parseInt(args[1]);
        double hotRatio = Double.parseDouble(args[2]);
        
        String[] durationParts = args[3].split(",");
        String[] threadParts = args[4].split(",");
        
        int[] phaseDurations = new int[durationParts.length];
        int[] phaseThreads = new int[threadParts.length];
        
        for (int i = 0; i < durationParts.length; i++) {
            phaseDurations[i] = Integer.parseInt(durationParts[i].trim());
        }
        for (int i = 0; i < threadParts.length; i++) {
            phaseThreads[i] = Integer.parseInt(threadParts[i].trim());
        }
        
        LoadGenerator.runScenarioE(totalKeys, hotKeys, hotRatio, phaseDurations, phaseThreads);
    }
}
