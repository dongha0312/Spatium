import { useEffect, useState } from "react";
import { getProjectList } from "../springApi/ProjectSpringBootAPi";

const EMPTY_STATS = {
  projectCount: 0,
  roomCount: 0,
};

function toCount(value) {
  const count = Number(value);
  return Number.isFinite(count) ? count : 0;
}

function useProjectStats(enabled) {
  const [stats, setStats] = useState(EMPTY_STATS);

  useEffect(() => {
    if (!enabled) {
      setStats(EMPTY_STATS);
      return undefined;
    }

    let active = true;

    getProjectList()
      .then((page) => {
        if (!active) return;

        const items = page?.items || [];
        const roomCount = items.reduce(
          (sum, project) =>
            sum + toCount(project?.roomCount ?? project?.roomCnt),
          0,
        );

        setStats({
          projectCount: items.length,
          roomCount,
        });
      })
      .catch((err) => {
        console.warn("프로젝트/룸 수 조회 실패:", err);
        if (active) setStats(EMPTY_STATS);
      });

    return () => {
      active = false;
    };
  }, [enabled]);

  return stats;
}

export default useProjectStats;
