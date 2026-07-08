import { useEffect, useState } from "react";
import { loadSceneConfig } from "../scene/sceneConfig";

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
