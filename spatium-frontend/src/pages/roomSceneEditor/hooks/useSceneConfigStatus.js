import { useEffect, useState } from "react";
import { loadSceneConfig } from "../scene/sceneConfig";

export function useSceneConfigStatus() {
  const [isSceneConfigReady, setSceneConfigReady] = useState(false);
  const [status, setStatus] = useState("Loading scene config...");
  const [error, setError] = useState("");

  useEffect(() => {
    let isMounted = true;

    setError("");
    setStatus("Loading scene config...");
    loadSceneConfig()
      .then(() => {
        if (!isMounted) return;
        setSceneConfigReady(true);
        setStatus("Loading room model...");
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
