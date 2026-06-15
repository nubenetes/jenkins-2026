package com.nubenetes.petclinic.billing.service.mapper;

import com.nubenetes.petclinic.billing.domain.Invoice;
import com.nubenetes.petclinic.billing.service.dto.InvoiceDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Invoice} and its DTO {@link InvoiceDTO}.
 */
@Mapper(componentModel = "spring")
public interface InvoiceMapper extends EntityMapper<InvoiceDTO, Invoice> {}
