import { describe, expect, it } from "vitest";
import type { Outgoing } from "../src/bridge";
import samples from "./fixtures/editor-messages.json";

// The Swift test `testEachEditorMessageSampleDecodes` decodes the same fixture.
// TypeScript widens the strings of a JSON import, so the fixture itself cannot
// satisfy `Outgoing[]`. This copy does, and the test keeps it equal to the fixture.
const typed = [
	{ action: "ready" },
	{ action: "change", path: "Tea.md", text: "# Tea\n\nGreen tea.\n" },
	{ action: "link", kind: "url", target: "https://example.com/tea" },
	{ action: "link", kind: "wiki", target: "Matcha#Shade" },
	{ action: "image", path: "Tea.md", type: "image/png", data: "iVBORw0KGgo=" },
	{ action: "lossy", path: "Tea.md", reasons: ["link titles"] },
	{ action: "explain", anchor: { quote: "less caffeine", block: 1, offset: 14 } },
	{ action: "define", anchor: { quote: "caffeine", block: 1, offset: 19 } },
	{ action: "ask", anchor: { quote: "less caffeine", block: 1, offset: 14 }, question: "How much less?" },
	{ action: "note", anchor: { quote: "less caffeine", block: 1, offset: 14 }, text: "Check the source." },
	{ action: "capture", text: "less caffeine" },
	{ action: "open", id: "6F9619FF-8B86-D011-B42D-00C04FC964FF" },
	{ action: "copy", id: "6F9619FF-8B86-D011-B42D-00C04FC964FF" },
	{ action: "continue", id: "6F9619FF-8B86-D011-B42D-00C04FC964FF" },
	{ action: "followup", id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", question: "And green tea?" },
] satisfies Outgoing[];

const actions = {
	ready: true,
	change: true,
	link: true,
	image: true,
	lossy: true,
	explain: true,
	define: true,
	ask: true,
	note: true,
	capture: true,
	open: true,
	copy: true,
	continue: true,
	followup: true,
} satisfies Record<Outgoing["action"], true>;

describe("editor messages", () => {
	it("are the messages of the bridge", () => {
		expect(samples).toEqual(typed);
	});

	it("have a sample for each action", () => {
		expect(new Set(samples.map((sample) => sample.action))).toEqual(new Set(Object.keys(actions)));
	});
});
