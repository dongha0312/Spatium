import { useEffect, useState } from "react";
import { loadSceneConfig } from "../scene/sceneConfig";

// room-scene-config.json을 앱 시작 시 한 번 로드하고, 로드 완료 여부/상태 메시지/에러를
// 관리한다. useRoomSceneEditor는 isSceneConfigReady가 true가 될 때까지 씬을 만들지 않는다.
export function useSceneConfigStatus() {
  const [isSceneConfigReady, setSceneConfigReady] = useState(false);
  const [status, setStatus] = useState("방 불러오는 중...");
  const [error, setError] = useState("");

  useEffect(() => {
    let isMounted = true;

    setError("");
    setStatus("방 불러오는 중...");
    loadSceneConfig()
      .then(() => {
        if (!isMounted) return;
        setSceneConfigReady(true);
        setStatus("방 불러오는 중...");
      })
      .catch((caughtError) => {
        if (!isMounted) return;
        setStatus("");
        setError(
          caughtError instanceof Error
            ? caughtError.message
            : String(caughtError),
        );
      });

    return () => {
      isMounted = false;
    };
  }, []);

  return {
    isSceneConfigReady,
    status,
    setStatus,
    error,
    setError,
  };
}
