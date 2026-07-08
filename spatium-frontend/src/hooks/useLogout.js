import { useCallback } from "react";
import { deleteLogout } from "../springApi/MemberSpringBootApi";
import { clearLoginSession, getAccessToken } from "../utils/authSession";

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
