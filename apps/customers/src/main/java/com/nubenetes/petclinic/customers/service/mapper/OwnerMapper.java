package com.nubenetes.petclinic.customers.service.mapper;

import com.nubenetes.petclinic.customers.domain.Customer;
import com.nubenetes.petclinic.customers.domain.Owner;
import com.nubenetes.petclinic.customers.service.dto.CustomerDTO;
import com.nubenetes.petclinic.customers.service.dto.OwnerDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Owner} and its DTO {@link OwnerDTO}.
 */
@Mapper(componentModel = "spring")
public interface OwnerMapper extends EntityMapper<OwnerDTO, Owner> {
    @Mapping(target = "customer", source = "customer", qualifiedByName = "customerId")
    OwnerDTO toDto(Owner s);

    @Named("customerId")
    @BeanMapping(ignoreByDefault = true)
    @Mapping(target = "id", source = "id")
    CustomerDTO toDtoCustomerId(Customer customer);
}
