import { fileURLToPath, URL } from "node:url";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import license from "rollup-plugin-license";
import icons from "unplugin-icons/vite";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

const local = (path: string) => fileURLToPath(new URL(path, import.meta.url));

export default defineConfig({
	base: "./",
	plugins: [
		// Hubble's components rely on the memoization that the React Compiler adds.
		react({
			babel: {
				plugins: [["babel-plugin-react-compiler", { compilationMode: "infer", target: "19" }]],
			},
		}),
		icons({ compiler: "jsx", jsx: "react" }),
		tailwindcss(),
		viteSingleFile(),
		license({
			thirdParty: {
				includePrivate: false,
				output: {
					file: local("./dist/licenses.txt"),
				},
			},
		}),
	],
	resolve: {
		alias: [
			{ find: "@hubble.md/editor/commands", replacement: local("./vendor/hubble/editor/commandRegistry.ts") },
			{ find: "@hubble.md/editor", replacement: local("./vendor/hubble/editor/index.ts") },
			{ find: "@hubble.md/ui", replacement: local("./vendor/hubble/ui/index.ts") },
		],
	},
	build: {
		outDir: "dist",
		emptyOutDir: true,
		target: "safari17",
		assetsInlineLimit: 100_000_000,
	},
	test: {
		environment: "happy-dom",
		include: ["test/**/*.test.ts", "vendor/hubble/editor/**/*.test.ts"],
	},
});
