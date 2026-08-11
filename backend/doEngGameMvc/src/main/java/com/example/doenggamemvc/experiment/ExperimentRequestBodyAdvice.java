package com.example.doenggamemvc.experiment;

import com.example.doenggamemvc.dto.ImageRequest;
import java.io.IOException;
import java.lang.reflect.Type;
import org.springframework.context.annotation.Profile;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpInputMessage;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.RequestBodyAdviceAdapter;

@ControllerAdvice
@Profile("experiment")
public class ExperimentRequestBodyAdvice extends RequestBodyAdviceAdapter {

    private final ExperimentPhaseTraceLogger traceLogger;

    public ExperimentRequestBodyAdvice(ExperimentPhaseTraceLogger traceLogger) {
        this.traceLogger = traceLogger;
    }

    @Override
    public boolean supports(
            MethodParameter methodParameter,
            Type targetType,
            Class<? extends HttpMessageConverter<?>> converterType) {
        return ImageRequest.class.isAssignableFrom(methodParameter.getParameterType());
    }

    @Override
    public HttpInputMessage beforeBodyRead(
            HttpInputMessage inputMessage,
            MethodParameter parameter,
            Type targetType,
            Class<? extends HttpMessageConverter<?>> converterType)
            throws IOException {
        traceLogger.event("BODY_READ_START");
        return inputMessage;
    }

    @Override
    public Object afterBodyRead(
            Object body,
            HttpInputMessage inputMessage,
            MethodParameter parameter,
            Type targetType,
            Class<? extends HttpMessageConverter<?>> converterType) {
        traceLogger.event("BODY_READ_END");
        return body;
    }

    @Override
    public Object handleEmptyBody(
            Object body,
            HttpInputMessage inputMessage,
            MethodParameter parameter,
            Type targetType,
            Class<? extends HttpMessageConverter<?>> converterType) {
        traceLogger.event("BODY_READ_END");
        return body;
    }
}
