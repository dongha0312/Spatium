package com.pknu.spatium_backend.dto;

import java.time.OffsetDateTime;
import java.util.List;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;

@Getter
@Setter
@NoArgsConstructor
@ToString
public class RoomMetadataDto {

    private OffsetDateTime createdAt;

    private String stylePrompt;

    private String notes;

    private List<String> replacementTargets;

    private List<String> preservedItems;
}