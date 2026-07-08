import { useCallback, useRef, useState } from "react";

export function useSelectionState() {
  const selectedObjectRef = useRef(null);
  const isReplacingSelectedRef = useRef(false);
  const [selectedItem, setSelectedItem] = useState(null);
  const [selectedRotationDegrees, setSelectedRotationDegreesState] =
    useState(0);
  const [selectedElevationCm, setSelectedElevationCmState] = useState(0);
  const [selectedMaxElevationCm, setSelectedMaxElevationCmState] =
    useState(0);
  const [isReplacingSelected, setReplacingSelected] = useState(false);

  const setReplaceMode = useCallback((active) => {
    isReplacingSelectedRef.current = active;
    setReplacingSelected(active);
  }, []);

  return {
    selectedObjectRef,
    isReplacingSelectedRef,
    selectedItem,
    setSelectedItem,
    selectedRotationDegrees,
    setSelectedRotationDegreesState,
    selectedElevationCm,
    setSelectedElevationCmState,
    selectedMaxElevationCm,
    setSelectedMaxElevationCmState,
    isReplacingSelected,
    setReplaceMode,
    canResetSelected: selectedItem?.sourceType === "object",
    canDeleteSelected: selectedItem?.sourceType === "object",
  };
}
