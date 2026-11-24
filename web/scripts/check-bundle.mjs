// Fails when Sources/Piper/Resources/editor.html differs from a fresh build of web/src.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const at = (path) => fileURLToPath(new URL(path, import.meta.url));
const built = readFileSync(at("../dist/index.html"));
const installed = readFileSync(at("../../Sources/Piper/Resources/editor.html"));
if (!built.equals(installed)) {
	console.error("Sources/Piper/Resources/editor.html does not match web/src. Run make web, and commit editor.html.");
	process.exit(1);
}
