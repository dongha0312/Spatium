// 기본적으로 React 라이브러리 불러들여놓기
import React from "react";

import { getTestData } from "../../springApi/TestSpringBootApi";

import { useEffect, useState } from "react";

function TestPage() {
  const [testData, setTestData] = useState(null);

  useEffect(() => {
    getTestData()
      .then((response) => {
        console.log(response.data);
        setTestData(response.data);
      })
      .catch((error) => {
        console.error(error);
      });
  }, []);
  return (
    <div>
      테스트 페이지 입니다
      <pre>{JSON.stringify(testData, null, 2)}</pre>
    </div>
  );
}

export default TestPage;
