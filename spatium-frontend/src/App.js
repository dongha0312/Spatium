// React 라이브러리 가져오기
import React from "react";

// React Router 라이브러리 가져오기
import { BrowserRouter } from "react-router-dom";
import HomeRouters from "./routers/HomeRouters";
import MemberRouters from "./routers/MemberRouters";
import AuthRouters from "./routers/AuthRouters";
import TestRouters from "./routers/TestRouters";




function App() {
    return (
        <BrowserRouter>
            <HomeRouters></HomeRouters>
            <MemberRouters></MemberRouters>
            <AuthRouters></AuthRouters>
            <TestRouters></TestRouters>
        </BrowserRouter>
    );
}

export default App;
