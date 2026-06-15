package com.nubenetes.petclinic.customers.domain;

import java.util.Random;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

public class OwnerTestSamples {

    private static final Random random = new Random();
    private static final AtomicLong longCount = new AtomicLong(random.nextInt() + (2 * Integer.MAX_VALUE));

    public static Owner getOwnerSample1() {
        return new Owner().id(1L).address("address1").city("city1").telephone("telephone1");
    }

    public static Owner getOwnerSample2() {
        return new Owner().id(2L).address("address2").city("city2").telephone("telephone2");
    }

    public static Owner getOwnerRandomSampleGenerator() {
        return new Owner()
            .id(longCount.incrementAndGet())
            .address(UUID.randomUUID().toString())
            .city(UUID.randomUUID().toString())
            .telephone(UUID.randomUUID().toString());
    }
}
