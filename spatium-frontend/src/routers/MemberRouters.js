// React 라이브러리 가지고 오기
import React from "react";

// URL 패턴에 따른 매핑 작업을 위한 라이브러리 가져오기
//  - Routes : 라우트 전체 관리  
//  - Route : 
import { Route, Routes } from "react-router-dom";
import MyPage from "../pages/member/MyPage";
import AccountSettings from "../pages/member/AccountSettings";
import ThreeDEditor from "../pages/3dEditor";
import ThreeDEditorDetail from "../pages/3dEditor_detail";


function MemberRouters(){
    return(
        <Routes>
            <Route path="member/mypage" element={<MyPage></MyPage>}></Route>
            <Route path="member/account" element={<AccountSettings></AccountSettings>}></Route>
            <Route path="member/editor" element={<ThreeDEditor></ThreeDEditor>}></Route>
            <Route path="member/editor/detail" element={<ThreeDEditorDetail></ThreeDEditorDetail>}></Route>
        </Routes>
    )
}

export default MemberRouters;