package com.nubenetes.petclinic.billing.security.jwt;

import com.nubenetes.petclinic.billing.config.SecurityConfiguration;
import com.nubenetes.petclinic.billing.config.SecurityJwtConfiguration;
import com.nubenetes.petclinic.billing.config.WebConfigurer;
import com.nubenetes.petclinic.billing.management.SecurityMetersService;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.test.context.SpringBootTest;
import tech.jhipster.config.JHipsterProperties;

@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@SpringBootTest(
    classes = {
        JHipsterProperties.class,
        WebConfigurer.class,
        SecurityConfiguration.class,
        SecurityJwtConfiguration.class,
        SecurityMetersService.class,
        JwtAuthenticationTestUtils.class,
    }
)
public @interface AuthenticationIntegrationTest {
}
