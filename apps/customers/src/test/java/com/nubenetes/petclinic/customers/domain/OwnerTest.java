package com.nubenetes.petclinic.customers.domain;

import static com.nubenetes.petclinic.customers.domain.CustomerTestSamples.*;
import static com.nubenetes.petclinic.customers.domain.OwnerTestSamples.*;
import static com.nubenetes.petclinic.customers.domain.PetTestSamples.*;
import static org.assertj.core.api.Assertions.assertThat;

import com.nubenetes.petclinic.customers.web.rest.TestUtil;
import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.Test;

class OwnerTest {

    @Test
    void equalsVerifier() throws Exception {
        TestUtil.equalsVerifier(Owner.class);
        Owner owner1 = getOwnerSample1();
        Owner owner2 = new Owner();
        assertThat(owner1).isNotEqualTo(owner2);

        owner2.setId(owner1.getId());
        assertThat(owner1).isEqualTo(owner2);

        owner2 = getOwnerSample2();
        assertThat(owner1).isNotEqualTo(owner2);
    }

    @Test
    void customerTest() {
        Owner owner = getOwnerRandomSampleGenerator();
        Customer customerBack = getCustomerRandomSampleGenerator();

        owner.setCustomer(customerBack);
        assertThat(owner.getCustomer()).isEqualTo(customerBack);

        owner.customer(null);
        assertThat(owner.getCustomer()).isNull();
    }

    @Test
    void petTest() {
        Owner owner = getOwnerRandomSampleGenerator();
        Pet petBack = getPetRandomSampleGenerator();

        owner.addPet(petBack);
        assertThat(owner.getPets()).containsOnly(petBack);
        assertThat(petBack.getOwner()).isEqualTo(owner);

        owner.removePet(petBack);
        assertThat(owner.getPets()).doesNotContain(petBack);
        assertThat(petBack.getOwner()).isNull();

        owner.pets(new HashSet<>(Set.of(petBack)));
        assertThat(owner.getPets()).containsOnly(petBack);
        assertThat(petBack.getOwner()).isEqualTo(owner);

        owner.setPets(new HashSet<>());
        assertThat(owner.getPets()).doesNotContain(petBack);
        assertThat(petBack.getOwner()).isNull();
    }
}
