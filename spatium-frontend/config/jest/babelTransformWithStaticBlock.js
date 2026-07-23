'use strict';

// react-scripts' default Jest transform doesn't enable static class blocks,
// which three.js (r150+) uses internally — needed once `three` is no longer
// excluded via transformIgnorePatterns (see package.json "jest" config).
const babelJest = require('babel-jest').default;

const hasJsxRuntime = (() => {
  if (process.env.DISABLE_NEW_JSX_TRANSFORM === 'true') {
    return false;
  }

  try {
    require.resolve('react/jsx-runtime');
    return true;
  } catch (e) {
    return false;
  }
})();

module.exports = babelJest.createTransformer({
  presets: [
    [
      require.resolve('babel-preset-react-app'),
      {
        runtime: hasJsxRuntime ? 'automatic' : 'classic',
      },
    ],
  ],
  plugins: [require.resolve('@babel/plugin-transform-class-static-block')],
  babelrc: false,
  configFile: false,
});
