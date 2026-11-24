// The rules of hooks and the React Compiler rules for the editor page.
// The vendored Hubble source in `vendor/` keeps its own style.
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";

export default tseslint.config(
	{ files: ["src/**/*.{ts,tsx}", "test/**/*.ts"] },
	{ languageOptions: { parser: tseslint.parser } },
	reactHooks.configs.flat.recommended,
);
