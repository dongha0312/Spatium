export function unwrapApiData(response) {
  return response?.data?.data ?? response?.data;
}

export function throwApiError(error) {
  const responseData = error.response?.data;
  // 백엔드 검증 실패 응답은 공통 message보다 errors[0].message에 더 구체적인 필드별 메시지가 들어옴.
  const fieldErrorMessage = Array.isArray(responseData?.errors)
    ? responseData.errors[0]?.message
    : null;

  const message =
    typeof responseData === "string"
      ? responseData
      : fieldErrorMessage || responseData?.message || error.message;

  const apiError = new Error(message);
  apiError.status = responseData?.statusCode || error.response?.status;
  apiError.code = responseData?.code;
  apiError.errors = responseData?.errors || [];
  apiError.response = error.response;
  throw apiError;
}
