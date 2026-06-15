package com.nubenetes.petclinic.billing.domain;

import static com.nubenetes.petclinic.billing.domain.InvoiceTestSamples.*;
import static com.nubenetes.petclinic.billing.domain.PaymentTestSamples.*;
import static org.assertj.core.api.Assertions.assertThat;

import com.nubenetes.petclinic.billing.web.rest.TestUtil;
import org.junit.jupiter.api.Test;

class PaymentTest {

    @Test
    void equalsVerifier() throws Exception {
        TestUtil.equalsVerifier(Payment.class);
        Payment payment1 = getPaymentSample1();
        Payment payment2 = new Payment();
        assertThat(payment1).isNotEqualTo(payment2);

        payment2.setId(payment1.getId());
        assertThat(payment1).isEqualTo(payment2);

        payment2 = getPaymentSample2();
        assertThat(payment1).isNotEqualTo(payment2);
    }

    @Test
    void invoiceTest() {
        Payment payment = getPaymentRandomSampleGenerator();
        Invoice invoiceBack = getInvoiceRandomSampleGenerator();

        payment.setInvoice(invoiceBack);
        assertThat(payment.getInvoice()).isEqualTo(invoiceBack);

        payment.invoice(null);
        assertThat(payment.getInvoice()).isNull();
    }
}
