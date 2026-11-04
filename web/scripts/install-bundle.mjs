// Copies the built page and its license list into the Piper sources.
import { copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const at = (path) => fileURLToPath(new URL(path, import.meta.url));
copyFileSync(at("../dist/index.html"), at("../../Sources/Piper/Resources/editor.html"));
copyFileSync(at("../dist/licenses.txt"), at("../../Licenses/Editor.txt"));
console.log("Installed Sources/Piper/Resources/editor.html and Licenses/Editor.txt");
