package com.example.cache;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class CachingMiddlewareApplication {

    public static void main(String[] args) {
        SpringApplication.run(CachingMiddlewareApplication.class, args);
    }
}
