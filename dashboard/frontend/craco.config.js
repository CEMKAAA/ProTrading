const path = require('path');

module.exports = {
  webpack: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
    configure: (webpackConfig, { env, paths }) => {
      // Disable react-refresh in development to prevent the error
      if (env === 'development') {
        webpackConfig.entry = webpackConfig.entry.filter(
          (entry) => !entry.includes('react-refresh')
        );
      }
      return webpackConfig;
    },
  },
  style: {
    postcss: {
      mode: 'extends',
      loaderOptions: (postcssLoaderOptions) => {
        postcssLoaderOptions.postcssOptions.plugins = [
          require('tailwindcss'),
          require('autoprefixer'),
        ];
        return postcssLoaderOptions;
      },
    },
  },
};
