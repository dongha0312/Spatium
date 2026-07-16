import { useEffect } from "react";
import { useLocation } from "react-router-dom";

// 라우트 이동 시 스크롤 위치를 항상 맨 위로 초기화합니다.
const ScrollToTop = () => {
  const { pathname } = useLocation();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);

  return null;
};

export default ScrollToTop;
