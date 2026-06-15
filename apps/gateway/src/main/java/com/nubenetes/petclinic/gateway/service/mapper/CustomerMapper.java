package com.nubenetes.petclinic.gateway.service.mapper;

import com.nubenetes.petclinic.gateway.domain.Customer;
import com.nubenetes.petclinic.gateway.service.dto.CustomerDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Customer} and its DTO {@link CustomerDTO}.
 */
@Mapper(componentModel = "spring")
public interface CustomerMapper extends EntityMapper<CustomerDTO, Customer> {}
