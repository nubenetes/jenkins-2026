package com.nubenetes.petclinic.gateway.service.mapper;

import com.nubenetes.petclinic.gateway.domain.Invoice;
import com.nubenetes.petclinic.gateway.domain.Payment;
import com.nubenetes.petclinic.gateway.service.dto.InvoiceDTO;
import com.nubenetes.petclinic.gateway.service.dto.PaymentDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Payment} and its DTO {@link PaymentDTO}.
 */
@Mapper(componentModel = "spring")
public interface PaymentMapper extends EntityMapper<PaymentDTO, Payment> {
    @Mapping(target = "invoice", source = "invoice", qualifiedByName = "invoiceId")
    PaymentDTO toDto(Payment s);

    @Named("invoiceId")
    @BeanMapping(ignoreByDefault = true)
    @Mapping(target = "id", source = "id")
    InvoiceDTO toDtoInvoiceId(Invoice invoice);
}
