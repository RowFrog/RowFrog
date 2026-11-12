// ESLint for the website (web/), the Cloudflare Workers (cloudflare/) and their
// tests. A small set of core rules that catch real mistakes, no style rules
// (formatting is a separate step) and no plugins: `npm ci` installs the pinned
// eslint from package-lock.json. Run with scripts/lint.sh, which only reports
// for now (good-practice doc, step 4); a later change makes new findings fail.
export default [
  { ignores: ["**/node_modules/**", "web/dist/**", "**/*.min.js", "**/vendor/**"] },
  {
    files: ["**/*.js", "**/*.mjs"],
    languageOptions: { ecmaVersion: 2024, sourceType: "module" },
    linterOptions: { reportUnusedDisableDirectives: "warn" },
    rules: {
      "no-unused-vars": ["warn", { args: "after-used", argsIgnorePattern: "^_", caughtErrors: "none" }],
      "no-shadow": "warn",
      // `x == null` (null or undefined) stays allowed; every other == must be ===.
      eqeqeq: ["warn", "always", { null: "ignore" }],
      "no-dupe-keys": "warn",
      "no-duplicate-case": "warn",
      "no-unreachable": "warn",
      "no-self-compare": "warn",
      "no-self-assign": "warn",
      "no-redeclare": "warn",
      "no-fallthrough": "warn",
      "no-cond-assign": "warn",
      "no-constant-condition": ["warn", { checkLoops: false }],
      "no-unsafe-finally": "warn",
      "no-unsafe-negation": "warn",
      "use-isnan": "warn",
      "valid-typeof": "warn",
      "no-sparse-arrays": "warn",
      "no-loss-of-precision": "warn",
    },
  },
];
