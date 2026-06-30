// React 라이브러리 가지고 오기
import React from "react";

// URL 패턴에 따른 매핑 작업을 위한 라이브러리 가져오기
//  - Routes : 라우트 전체 관리  
//  - Route : 
import { Route, Routes } from "react-router-dom";

// 외부 컴포넌트 가지고 오기
// 공통으로 사용할 메인 메뉴 페이지 : HomePage.js
import HomePage from "../pages/HomePage";

import TestPage from "../pages/TestPage";

// HomeRouters.js 컴포넌트 정의하기
function HomeRouters() {
    return(
        /** Routes 컴포넌트로 전체 감싸기
         *  - import Routes 및 Route 필요함
         */
        <Routes>
            {/* URL 패턴 및 매핑 컴포넌트 정의 */}

            {/* 루트(http://localhost:3000/) URL로 들어오면 -> HomePage.js 페이지 호출하기  */}
            <Route path="/" element={<HomePage></HomePage>}></Route>
            <Route path="/test" element={<TestPage></TestPage>}></Route>

        </Routes>
    );
}

// 외부에서 불러들일때(import) 사용하기 위해 export(내보내기) 처리
export default HomeRouters;
