package com.nubenetes.petclinic.customers.domain;

import java.util.Random;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

public class PetTestSamples {

    private static final Random random = new Random();
    private static final AtomicLong longCount = new AtomicLong(random.nextInt() + (2 * Integer.MAX_VALUE));

    public static Pet getPetSample1() {
        return new Pet().id(1L).name("name1");
    }

    public static Pet getPetSample2() {
        return new Pet().id(2L).name("name2");
    }

    public static Pet getPetRandomSampleGenerator() {
        return new Pet().id(longCount.incrementAndGet()).name(UUID.randomUUID().toString());
    }
}
