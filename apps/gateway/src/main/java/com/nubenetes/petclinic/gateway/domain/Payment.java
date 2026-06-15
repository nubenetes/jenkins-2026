package com.nubenetes.petclinic.gateway.domain;

import com.nubenetes.petclinic.gateway.domain.enumeration.PaymentMethod;
import jakarta.validation.constraints.*;
import java.io.Serializable;
import java.math.BigDecimal;
import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/**
 * A Payment.
 */
@Table("payment")
@SuppressWarnings("common-java:DuplicatedBlocks")
public class Payment implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @Column("id")
    private Long id;

    @NotNull(message = "must not be null")
    @Column("amount")
    private BigDecimal amount;

    @NotNull(message = "must not be null")
    @Column("payment_date")
    private Instant paymentDate;

    @NotNull(message = "must not be null")
    @Column("method")
    private PaymentMethod method;

    @org.springframework.data.annotation.Transient
    private Invoice invoice;

    @Column("invoice_id")
    private Long invoiceId;

    // jhipster-needle-entity-add-field - JHipster will add fields here

    public Long getId() {
        return this.id;
    }

    public Payment id(Long id) {
        this.setId(id);
        return this;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public BigDecimal getAmount() {
        return this.amount;
    }

    public Payment amount(BigDecimal amount) {
        this.setAmount(amount);
        return this;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount != null ? amount.stripTrailingZeros() : null;
    }

    public Instant getPaymentDate() {
        return this.paymentDate;
    }

    public Payment paymentDate(Instant paymentDate) {
        this.setPaymentDate(paymentDate);
        return this;
    }

    public void setPaymentDate(Instant paymentDate) {
        this.paymentDate = paymentDate;
    }

    public PaymentMethod getMethod() {
        return this.method;
    }

    public Payment method(PaymentMethod method) {
        this.setMethod(method);
        return this;
    }

    public void setMethod(PaymentMethod method) {
        this.method = method;
    }

    public Invoice getInvoice() {
        return this.invoice;
    }

    public void setInvoice(Invoice invoice) {
        this.invoice = invoice;
        this.invoiceId = invoice != null ? invoice.getId() : null;
    }

    public Payment invoice(Invoice invoice) {
        this.setInvoice(invoice);
        return this;
    }

    public Long getInvoiceId() {
        return this.invoiceId;
    }

    public void setInvoiceId(Long invoice) {
        this.invoiceId = invoice;
    }

    // jhipster-needle-entity-add-getters-setters - JHipster will add getters and setters here

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof Payment)) {
            return false;
        }
        return getId() != null && getId().equals(((Payment) o).getId());
    }

    @Override
    public int hashCode() {
        // see https://vladmihalcea.com/how-to-implement-equals-and-hashcode-using-the-jpa-entity-identifier/
        return getClass().hashCode();
    }

    // prettier-ignore
    @Override
    public String toString() {
        return "Payment{" +
            "id=" + getId() +
            ", amount=" + getAmount() +
            ", paymentDate='" + getPaymentDate() + "'" +
            ", method='" + getMethod() + "'" +
            "}";
    }
}
