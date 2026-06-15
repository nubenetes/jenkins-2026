package com.nubenetes.petclinic.billing.domain;

import static com.nubenetes.petclinic.billing.domain.InvoiceTestSamples.*;
import static com.nubenetes.petclinic.billing.domain.PaymentTestSamples.*;
import static org.assertj.core.api.Assertions.assertThat;

import com.nubenetes.petclinic.billing.web.rest.TestUtil;
import org.junit.jupiter.api.Test;

class InvoiceTest {

    @Test
    void equalsVerifier() throws Exception {
        TestUtil.equalsVerifier(Invoice.class);
        Invoice invoice1 = getInvoiceSample1();
        Invoice invoice2 = new Invoice();
        assertThat(invoice1).isNotEqualTo(invoice2);

        invoice2.setId(invoice1.getId());
        assertThat(invoice1).isEqualTo(invoice2);

        invoice2 = getInvoiceSample2();
        assertThat(invoice1).isNotEqualTo(invoice2);
    }

    @Test
    void paymentTest() {
        Invoice invoice = getInvoiceRandomSampleGenerator();
        Payment paymentBack = getPaymentRandomSampleGenerator();

        invoice.setPayment(paymentBack);
        assertThat(invoice.getPayment()).isEqualTo(paymentBack);
        assertThat(paymentBack.getInvoice()).isEqualTo(invoice);

        invoice.payment(null);
        assertThat(invoice.getPayment()).isNull();
        assertThat(paymentBack.getInvoice()).isNull();
    }
}
