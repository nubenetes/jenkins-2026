package com.nubenetes.petclinic.customers.service.dto;

import java.io.Serializable;
import java.util.Objects;

/**
 * A DTO for the {@link com.nubenetes.petclinic.customers.domain.Owner} entity.
 */
@SuppressWarnings("common-java:DuplicatedBlocks")
public class OwnerDTO implements Serializable {

    private Long id;

    private String address;

    private String city;

    private String telephone;

    private CustomerDTO customer;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public String getCity() {
        return city;
    }

    public void setCity(String city) {
        this.city = city;
    }

    public String getTelephone() {
        return telephone;
    }

    public void setTelephone(String telephone) {
        this.telephone = telephone;
    }

    public CustomerDTO getCustomer() {
        return customer;
    }

    public void setCustomer(CustomerDTO customer) {
        this.customer = customer;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof OwnerDTO)) {
            return false;
        }

        OwnerDTO ownerDTO = (OwnerDTO) o;
        if (this.id == null) {
            return false;
        }
        return Objects.equals(this.id, ownerDTO.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(this.id);
    }

    // prettier-ignore
    @Override
    public String toString() {
        return "OwnerDTO{" +
            "id=" + getId() +
            ", address='" + getAddress() + "'" +
            ", city='" + getCity() + "'" +
            ", telephone='" + getTelephone() + "'" +
            ", customer=" + getCustomer() +
            "}";
    }
}
