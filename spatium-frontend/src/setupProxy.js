const { createProxyMiddleware } = require("http-proxy-middleware");

module.exports = function (app) {
  const springBootTarget = "http://210.119.12.101:8080";

  app.use(
    "/api",
    createProxyMiddleware({
      target: springBootTarget,
      changeOrigin: true,
      secure: false,
    }),
  );
};
