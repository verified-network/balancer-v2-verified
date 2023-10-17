module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint', 'prettier', 'mocha-no-only'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
  rules: {
    'comma-spacing': ['error', { before: false, after: true }],
    'mocha-no-only/mocha-no-only': ['error'],
    'prettier/prettier': [
      'error',
      {
        endOfFile: 'auto',
      },
    ],
  },
};
