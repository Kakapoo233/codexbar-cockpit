// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { FloatingSummary, type FloatingSummaryProps } from "./FloatingSummary";
import { DEFAULT_WIDGET_PREFERENCES } from "../lib/preferences";
import { buildCockpitDailyPlan } from "../lib/cockpitDailyPlan";
import type { ProviderSnapshot } from "../types";

afterEach(cleanup);
const now = new Date("2026-11-01T12:00:00Z");
const codex: ProviderSnapshot = {
  provider: "codex", accountScope: "synthetic-account", displayName: "CODEX", plan: "PRO",
  shortWindow: { remainingPercent: 65, resetsAt: null, windowSeconds: 18_000 },
  weeklyWindow: { remainingPercent: 74, resetsAt: null, windowSeconds: 604_800 },
  updatedAt: now.toISOString(), resetCredits: null, status: "ok", message: null,
};
function fixture(): FloatingSummaryProps {
  return {
    preferences: { ...DEFAULT_WIDGET_PREFERENCES, language: "en", trayMode: "percent" }, snapshots: [codex],
    plan: { ...buildCockpitDailyPlan({ providerID: "codex", accountID: "synthetic-account", now, snapshots: [] }),
      remainingDailyBudgetPercent: 75, remainingSuggestedPercent: 15, suggestedPercent: 20,
      isStale: false, suggestionIsPartial: false, coverage: "complete" },
    startupReady: true, refreshing: false, error: null,
    onOpen: vi.fn(), onHide: vi.fn(), onDrag: vi.fn(), onRefresh: vi.fn(),
  };
}

it("keeps today's allocation ratio separate from weekly quota and recommendation", () => {
  render(<FloatingSummary {...fixture()} />);
  expect(screen.getByText("65%")).toBeInTheDocument();
  expect(screen.getByText("74%")).toBeInTheDocument();
  expect(screen.getByLabelText("Available today: 75% of today's allocation; weekly equivalent 15%")).toHaveTextContent("75%");
  expect(screen.getByTitle("Full-day recommendation, as a share of weekly quota")).toHaveTextContent("T 20% recommended / week");
  expect(screen.getByText("T")).toBeInTheDocument();
});

it.each(["bar", "circle"] as const)("renders %s as remaining fill and distinguishes unknown from measured zero", mode => {
  const props = fixture(); props.preferences.trayMode = mode;
  const { container, rerender } = render(<FloatingSummary {...props} />);
  const meter = container.querySelector(".floating-summary-meter")!;
  expect(meter).toHaveAttribute("data-state", "known");
  expect(meter).toHaveAccessibleName(/75% of today's allocation; weekly equivalent 15%/);
  expect(meter.querySelector(".floating-summary-meter-fill")).toHaveStyle(mode === "bar" ? { width: "75%" } : { height: "75%" });
  rerender(<FloatingSummary {...props} plan={{ ...props.plan, remainingDailyBudgetPercent: 0, remainingSuggestedPercent: 0 }} />);
  expect(meter).toHaveAttribute("data-state", "known");
  expect(meter).toHaveAccessibleName(/0% of today's allocation; weekly equivalent 0%/);
  expect(meter.querySelector(".floating-summary-meter-fill")).toHaveStyle(mode === "bar" ? { width: "0%" } : { height: "0%" });
  rerender(<FloatingSummary {...props} plan={{ ...props.plan, remainingDailyBudgetPercent: null, remainingSuggestedPercent: null }} />);
  expect(meter).toHaveAttribute("data-state", "unknown");
  expect(meter).toHaveAccessibleName("Available today: unavailable");
  expect(meter).toHaveTextContent("—");
});

it.each([
  { remaining: 44.3, stale: false, center: "44%", description: "Available today: 44.3% of today's allocation; weekly equivalent 8.9%" },
  { remaining: 100, stale: true, center: "≈100%", description: "Available today: 100% of today's allocation; weekly equivalent 8.9%; data may be stale" },
])("keeps precise circle details with a compact center at $remaining%", entry => {
  const props = fixture();
  props.preferences.trayMode = "circle";
  props.plan = { ...props.plan, remainingDailyBudgetPercent: entry.remaining, remainingSuggestedPercent: 8.9, isStale: entry.stale };
  const { container, rerender } = render(<FloatingSummary {...props} />);
  const meter = screen.getByRole("img", { name: entry.description });
  expect(meter.querySelector("strong")).toHaveTextContent(entry.center);
  expect(meter.querySelector("strong")?.textContent).toBe(entry.center);
  expect(container.querySelector(".floating-summary-today")).toHaveAttribute("title", entry.description);
  expect(meter.querySelector(".floating-summary-meter-fill")).toHaveStyle({ height: `${entry.remaining}%` });
  props.preferences.trayMode = "bar";
  rerender(<FloatingSummary {...props} />);
  expect(screen.getByRole("img", { name: entry.description })).toHaveTextContent(`${entry.stale ? "≈" : ""}${entry.remaining}%`);
  props.preferences.trayMode = "percent";
  rerender(<FloatingSummary {...props} />);
  expect(screen.getByLabelText(entry.description)).toHaveTextContent(`${entry.stale ? "≈" : ""}${entry.remaining}%`);
});

it.each(["hidden", "disabled", "absent", "signed_out", "loading"] as const)("suppresses Codex and planner readings when %s", state => {
  const props = fixture();
  props.snapshots = [{ ...codex, provider: "qoder", weeklyWindow: { remainingPercent: 99, resetsAt: null, windowSeconds: 604_800 } }, codex];
  if (state === "hidden") props.preferences.hiddenProviders = ["codex"];
  if (state === "disabled") props.preferences.enabledProviders = ["qoder"];
  if (state === "absent") props.snapshots = props.snapshots.filter(value => value.provider !== "codex");
  if (state === "signed_out") props.snapshots = [{ ...codex, status: "signed_out" }];
  if (state === "loading") props.startupReady = false;
  render(<FloatingSummary {...props} />);
  expect(screen.queryByText("65%")).not.toBeInTheDocument();
  expect(screen.queryByText("74%")).not.toBeInTheDocument();
  expect(screen.queryByText("75%")).not.toBeInTheDocument();
  expect(screen.queryByText("99%")).not.toBeInTheDocument();
  expect(screen.getByTitle("Full-day recommendation, as a share of weekly quota")).toHaveTextContent("T —");
});

it("keeps uncertainty accessible while omitting visible upper-bound glyphs", () => {
  const props = fixture();
  props.snapshots = [{ ...codex, status: "stale" }]; props.plan.coverage = "partial";
  const { container } = render(<FloatingSummary {...props} />);
  expect(screen.getByText("≈65%")).toBeInTheDocument();
  expect(screen.getByText("≈74%")).toBeInTheDocument();
  expect(screen.getByLabelText("Available today: ≤75% of today's allocation; weekly equivalent ≤15%; data may be stale")).toHaveTextContent("≈75%");
  expect(container.textContent).not.toContain("≤");
});

it("opens details/settings, hides, retries and drags only from the primary-pointer header background", () => {
  const props = fixture(); props.error = "synthetic collection error";
  const { container } = render(<FloatingSummary {...props} />);
  const header = container.querySelector(".floating-summary-header")!;
  const settings = screen.getByRole("button", { name: "Settings" });
  fireEvent(settings, new MouseEvent("pointerdown", { bubbles: true, button: 0 }));
  expect(props.onDrag).not.toHaveBeenCalled();
  fireEvent.click(settings); fireEvent.click(screen.getByRole("button", { name: "Open full panel" }));
  expect(props.onOpen).toHaveBeenNthCalledWith(1, "settings"); expect(props.onOpen).toHaveBeenNthCalledWith(2, "usage");
  fireEvent.click(screen.getByRole("button", { name: "Hide floating window" })); expect(props.onHide).toHaveBeenCalledOnce();
  fireEvent.click(screen.getByRole("button", { name: "Retry" })); expect(props.onRefresh).toHaveBeenCalledOnce();
  fireEvent(header, new MouseEvent("pointerdown", { bubbles: true, button: 2 })); expect(props.onDrag).not.toHaveBeenCalled();
  fireEvent(header, new MouseEvent("pointerdown", { bubbles: true, button: 0 })); expect(props.onDrag).toHaveBeenCalledOnce();
  expect(container.textContent).not.toContain(props.error);
});
