package com.nubenetes.petclinic.gateway.domain;

import static com.nubenetes.petclinic.gateway.domain.CustomerTestSamples.*;
import static com.nubenetes.petclinic.gateway.domain.OwnerTestSamples.*;
import static org.assertj.core.api.Assertions.assertThat;

import com.nubenetes.petclinic.gateway.web.rest.TestUtil;
import org.junit.jupiter.api.Test;

class CustomerTest {

    @Test
    void equalsVerifier() throws Exception {
        TestUtil.equalsVerifier(Customer.class);
        Customer customer1 = getCustomerSample1();
        Customer customer2 = new Customer();
        assertThat(customer1).isNotEqualTo(customer2);

        customer2.setId(customer1.getId());
        assertThat(customer1).isEqualTo(customer2);

        customer2 = getCustomerSample2();
        assertThat(customer1).isNotEqualTo(customer2);
    }

    @Test
    void ownerTest() {
        Customer customer = getCustomerRandomSampleGenerator();
        Owner ownerBack = getOwnerRandomSampleGenerator();

        customer.setOwner(ownerBack);
        assertThat(customer.getOwner()).isEqualTo(ownerBack);
        assertThat(ownerBack.getCustomer()).isEqualTo(customer);

        customer.owner(null);
        assertThat(customer.getOwner()).isNull();
        assertThat(ownerBack.getCustomer()).isNull();
    }
}
