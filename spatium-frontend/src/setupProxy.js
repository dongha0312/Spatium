const { createProxyMiddleware } = require("http-proxy-middleware");

module.exports = function (app) {
  const springBootTarget = "http://localhost:8080";

  app.use(
    "/api",
    createProxyMiddleware({
      target: springBootTarget,
      changeOrigin: true,
      secure: false,
    }),
  );

  app.use(
    "/spring",
    createProxyMiddleware({
      target: springBootTarget,
      changeOrigin: true,
      secure: false,
      pathRewrite: {
        "^/spring": "",
      },
    }),
  );
};
