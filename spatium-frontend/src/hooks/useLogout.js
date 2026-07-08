import { useCallback } from "react";
import { deleteLogout } from "../springApi/MemberSpringBootApi";
import { clearLoginSession, getAccessToken } from "../utils/authSession";

// 로그아웃 API 호출과 로컬 로그인 세션 정리를 한 곳에서 처리합니다.
function useLogout(onAfterLogout) {
  return useCallback(async () => {
    try {
      if (getAccessToken()) {
        await deleteLogout();
      }
    } catch (err) {
      console.warn("Logout API failed, clearing local session anyway.", err);
    }

    clearLoginSession();
    onAfterLogout?.();
  }, [onAfterLogout]);
}

export default useLogout;
