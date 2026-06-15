package com.nubenetes.petclinic.billing.service.mapper;

import com.nubenetes.petclinic.billing.domain.Invoice;
import com.nubenetes.petclinic.billing.domain.Payment;
import com.nubenetes.petclinic.billing.service.dto.InvoiceDTO;
import com.nubenetes.petclinic.billing.service.dto.PaymentDTO;
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
