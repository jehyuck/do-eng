package com.example.doenggamemvc.dto;

public class AiDecisionResponse {

    private boolean result;
    private String image;

    public boolean isResult() {
        return result;
    }

    public void setResult(boolean result) {
        this.result = result;
    }

    public String getImage() {
        return image;
    }

    public void setImage(String image) {
        this.image = image;
    }
}
