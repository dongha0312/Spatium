// React 라이브러리 가지고 오기
import React from "react";

// URL 패턴에 따른 매핑 작업을 위한 라이브러리 가져오기
//  - Routes : 라우트 전체 관리  
//  - Route : 
import { Route, Routes } from "react-router-dom";
import TestThreeStagingPage from "../pages/testThree/TestThreeStagingPage";


function TestRouters(){
    return(
        <Routes>
            <Route path="/test/three" element={<TestThreeStagingPage></TestThreeStagingPage>}></Route>
        </Routes>
    )
}

export default TestRouters;
