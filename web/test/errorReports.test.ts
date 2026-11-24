import { describe, expect, it } from "vitest";
import { errorFilter } from "../src/errorReports";

describe("errorFilter", () => {
	it("passes each distinct message once", () => {
		const shouldReport = errorFilter();
		expect(shouldReport("a")).toBe(true);
		expect(shouldReport("b")).toBe(true);
		expect(shouldReport("a")).toBe(false);
	});

	it("drops ResizeObserver loop messages", () => {
		const shouldReport = errorFilter();
		expect(shouldReport("ResizeObserver loop completed with undelivered notifications.")).toBe(false);
		expect(shouldReport("ResizeObserver loop limit exceeded")).toBe(false);
	});
});
