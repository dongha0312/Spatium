const { createProxyMiddleware } = require("http-proxy-middleware");

module.exports = function (app) {
  const springBootTarget = "http://localhost:8080";
  const imageTo3dTarget = "http://localhost:8000";

  app.use(
    "/img3d-api",
    createProxyMiddleware({
      target: imageTo3dTarget,
      changeOrigin: true,
      secure: false,
      pathRewrite: {
        "^/img3d-api": "",
      },
    }),
  );

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
