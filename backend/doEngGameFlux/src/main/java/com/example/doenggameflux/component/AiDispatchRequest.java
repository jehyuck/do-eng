package com.example.doenggameflux.component;

import com.example.doenggameflux.dto.request.ImageRequestDto;
import java.util.Objects;

public final class AiDispatchRequest {

    private final ImageRequestDto image;
    private final String answer;
    private final String aiPath;
    private final RequestIdentity requestIdentity;

    public AiDispatchRequest(
            ImageRequestDto image,
            String answer,
            String aiPath,
            RequestIdentity requestIdentity) {
        this.image = Objects.requireNonNull(image, "image");
        this.answer = Objects.requireNonNull(answer, "answer");
        this.aiPath = Objects.requireNonNull(aiPath, "aiPath");
        this.requestIdentity = Objects.requireNonNull(requestIdentity, "requestIdentity");
    }

    public ImageRequestDto getImage() {
        return image;
    }

    public String getAnswer() {
        return answer;
    }

    public String getAiPath() {
        return aiPath;
    }

    public RequestIdentity getRequestIdentity() {
        return requestIdentity;
    }
}
