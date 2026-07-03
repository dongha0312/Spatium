export function unwrapApiData(response) {
  return response?.data?.data ?? response?.data;
}

export function throwApiError(error) {
  const responseData = error.response?.data;
  const message =
    typeof responseData === "string"
      ? responseData
      : responseData?.message || error.message;

  const apiError = new Error(message);
  apiError.status = responseData?.statusCode || error.response?.status;
  apiError.code = responseData?.code;
  apiError.errors = responseData?.errors || [];
  apiError.response = error.response;
  throw apiError;
}
