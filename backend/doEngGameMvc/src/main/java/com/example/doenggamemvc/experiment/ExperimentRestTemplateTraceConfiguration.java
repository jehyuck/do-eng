package com.example.doenggamemvc.experiment;

import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.web.client.RestTemplate;

@Configuration
@Profile("experiment")
public class ExperimentRestTemplateTraceConfiguration {

    @Bean
    public static BeanPostProcessor experimentRestTemplateTracePostProcessor(
            ExperimentRestTemplateTraceInterceptor interceptor) {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(
                    Object bean,
                    String beanName)
                    throws BeansException {
                if (!(bean instanceof RestTemplate)
                        || !"externalRestTemplate".equals(beanName)) {
                    return bean;
                }
                RestTemplate restTemplate = (RestTemplate) bean;
                List<?> existing = restTemplate.getInterceptors();
                if (existing.stream().noneMatch(
                        item -> item instanceof ExperimentRestTemplateTraceInterceptor)) {
                    List<org.springframework.http.client.ClientHttpRequestInterceptor> updated =
                            new ArrayList<>();
                    updated.addAll(restTemplate.getInterceptors());
                    updated.add(interceptor);
                    restTemplate.setInterceptors(updated);
                }
                return bean;
            }
        };
    }
}
