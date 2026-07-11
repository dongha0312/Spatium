import { useCallback, useRef, useState } from "react";

// 현재 선택된 오브젝트(ref)와, 선택 정보를 화면에 보여주기 위한 React state를 관리한다.
// 선택 자체는 ref로 즉시 접근 가능하게 두고, 화면 표시용 값만 state로 동기화한다.
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

  // 교체 모드 on/off. ref는 pointer 이벤트 핸들러 안에서 즉시 참조하기 위함이고,
  // state는 버튼 활성화 표시 등 화면 갱신용이다.
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
