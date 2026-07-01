/**
 * 파일명은 React에서 정해진 이름으로 수정하면 안됨
 *  - React 실행 시 자동으로 해당 파일을 찾아서 로딩하게 됩니다.
 *  - 파일의 위치는 src 폴더 안에 위치해야 합니다.
 *
 * <setupProxy.js 파일은 언제, 어디서 호출될까?>
 *  1. npm start 시에 node_modules/react-scripts/scripts/start.js 파일이 실행됨
 *
 *  2. start.js : 개발 서버를 띄우기 위한 준비 작업을 수행하는 파일
 *      - start.js 파일에서
 *         -> node_modules/react-scripts/config/webpackDevServer.config.js 파일을 찾아서 로딩함
 *         -> start.js 파일 내에(41번째 줄)
 *          --> "const config = require('../config/webpackDevServer.config');" 정의되어 있음
 *
 *  3. webpackDevServer.config.js : 개발 서버 설정 파일 체크하는 파일(117번째 줄)
 *     - if (fs.existsSync(paths.proxySetup)) { ... } 구문에서 setupProxy.js 파일이 존재하는지 체크함
 *     - 이때, proxySetup은 node_modules/react-scripts/config/paths.js 파일에서 정의된 proxySetup 변수임
 *       -> paths.js 파일 내에(75번째 줄)
 *          --> "proxySetup: resolveApp('src/setupProxy.js')"로 정의되어 있음
 */



// React에서 백엔드서버로 전송하기 위한 라이브러리 사용
const {createProxyMiddleware} = require("http-proxy-middleware");

// 프록시(Proxy) 서버 처리를 하는 이유??
//  - 프록시(Proxy) 설정은 브라우저 페이지 간 데이터 주고 받는 것을 허용하기 위한 방법으로,
//    -> 이 CORS 정책을 우회하는 방법임(아래 CORS 설명 참조)
//    -> 프록시(Proxy)란? : 대리인이라는 뜻으로,
//       : 중간에서 요청과 응답을 대신 처리하는 역할을 하는 서버를 의미함
//    -> 브라우저에서 요청이 발생하면,
//       : 프록시 서버가 이 요청을 가로채서 (크롬)브라우저를 통하지 않고,
//          --> 네트워크를 통해서, 다른 서버로 요청을 보내고, 응답 받는 방식임
//          --> 다른 서버로부터 응답 받은 정보를 React 내부에서 처리한 후,
//          --> (크롬)브라우저에서는 처리된 결과만 보여주게 됨
//          --> 브라우저는 뒤에서 무슨 일이 벌어지는지 알 수 없음
//              (프록시 서버가 중간에서 처리하기 때문에..CORS 정책을 우회할 수 있음)

// CORS 란??
//  - CORS는 Cross-Origin Resource Sharing(교차 출처 리소스 공유)의 약자
//  - CORS는 브라우저 자체 보안 정책임
//  - CORS 에러는 브라우저가 "요청을 보낸 곳(Origin)"과 "요청을 받는 곳"이 다를 때 발생
//  - 하나의 서버 주소(포트)에서 실행된 브라우저 페이지 내에서는
//    -> 다른 서버 주소(포트 포함)의 내부 자원에 요청 할 수 없음
//       (브라우저 페이지 간 데이터 주고 받는 것을 제한하는 보안 정책)
//    -> 브라우저 만의 보안 정책임(각 브러우저에서 적용됨)
//  - 서로 다른 서버란?
//    -> localhost:3000과 localhost:8080은 서로 다른 서버로 인식됨
//    -> 서버 주소는 같더라도, 포트 번호가 다르면 서로 다른 서버로 인식됨

// React 서버 실행시 자동으로 setupProxy.js 파일이 로딩되어서 Proxy 설정이 적용됨
//  - React 서버에서 URL : http://localhost:3000/react/springboot_test 로 요청이 시작되면,
//    -> 중간에 setupProxy.js가 URL을 가로챈 후,
//    -> axiosInstance.js에서 설정한 springApi 인스턴스의 baseURL(http://localhost:8080)과 결합하여
//    -> http://localhost:8080/react/springboot_test로 변경해서 SpringBoot로 요청 진행함
// - app : 요청하는 시점을 의미함(요청자)



// 실제 프록시 실행 처리
//  - app은 요청자, 즉 요청하는 시점을 의미적으로 부여함
module.exports = function (app) {
    /** SpringBoot 서버 간의 프록시 설정 정의 */
    // 현재 요청 시점의 정보를 받아서 처리(app이 가지고 있음)
    //  - 최초 요청은 TestSpringBootApi.js에서 시작됨 
    app.use(
        // 대표 baseURL 패턴 정의
        //  - axiosInstance.js에서 호출 시 사용한 baseURL 이니셜로 선택됨 
        //  - 변경된 URL로 받아옴 : http://localhost:3000/spring/react/springboot_test
        //    -> 도메인 주소(포트) 뒤에 첫번째 경로가 /spring인지 확인 
        "/spring",

        // 서버 주소 및 포트 설정 변경 처리
        createProxyMiddleware({
            // 요청을 보낼 백엔드 실제 서버 주소 설정
            // target : "http://localhost:8080",
            target : "http://localhost:8080",

            // 요청을 보내는 주소(프론트엔드)를 백엔드 주소로 바꿔치기 하기
            //  - 실제 URL 주소가 바뀌는 부분
            changeOrigin : true, 

            // HTTP 요청 시 인증서 검증 처리 사용 여부
            //  - secure : ture는 https 프로토콜도 사용 가능
            //  - secure : false는 http만 사용
            "secure" : true,

            // 위에 설정된 속성값을 이용하여 -> URL 경로를 재정의
            // URL : http://localhost:3000/spring/react/springboot_test
            // 1차 서버 주소로 변경 
            //   : http://localhost:8080/spring/react/springboot_test
            // 2차 /spring 제거하기
            //   : "^/spring" -> 변경할 부분을 찾는 정규표현식
            //                -> ^ 뒤에 문자열 부분을 찾아서
            //                -> : "" 공백으로 치환(바꿔치기, 제거 의미를 가짐)
            //   http://localhost:3000/react/springboot_test
            // <SpringBoot Controller 폴더 내에 Day0506_ReactTest.java 파일 생성>
            //  - URL 패턴 : /react/springboot_test
            //  - 메서드명 : getReactSpringBootTest
            //  - 반환타입 : ResponseEntity<String>
            //  - 반환 값 : "React에서 SpringBoot로 연결이 성공되었습니다"
            pathRewrite : {
                "^/spring" : "",
            },
        })
        
    );
};