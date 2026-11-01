// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { TrayPanel, confirmedReset } from "./TrayPanel";
import { DEFAULT_WIDGET_PREFERENCES } from "../lib/preferences";
import { buildCockpitDailyPlan } from "../lib/cockpitDailyPlan";
import { personalizeComfortCurve } from "../lib/comfortFeedback";
import type { ResetForecast } from "../types";
vi.mock("../lib/bridge", () => ({ isTauri: () => false, openExternalUrl: vi.fn() }));
vi.mock("./CodexUsagePanel", () => ({ CodexUsagePanel: (props: { externalRange: { start: string; end: string } | null }) => <div data-testid="usage-range">{props.externalRange ? `${props.externalRange.start}/${props.externalRange.end}` : "all"}</div> }));
vi.mock("./TeamMemberSettings", () => ({ TeamMemberSettings: () => <p>Member editor</p> }));
vi.mock("./CloudSyncSettings", () => ({ CloudSyncSettings: () => <p>Cloud settings</p> }));
vi.mock("./LocalUsageSourceSettings", () => ({ LocalUsageSourceSettings: () => <p>Local source</p> }));
afterEach(cleanup);
const now = new Date("2026-11-01T12:00:00Z");
function props() {
  return { preferences: { ...DEFAULT_WIDGET_PREFERENCES, language: "en" as const }, onPreferences: vi.fn(), snapshots: [],
    plan: buildCockpitDailyPlan({ providerID: "codex", accountID: null, now, snapshots: [] }), history: [], forecast: null,
    now, usage: null, usageError: false, onUsageRefresh: vi.fn(async () => undefined), diagnostics: null, startupReady: true,
    settingsWritable: true, error: null, onDismissError: vi.fn(), refreshing: false, onRefresh: vi.fn(), onHide: vi.fn(),
    onFeedback: vi.fn(), feedback: [], dailyUsage: [], curve: personalizeComfortCurve([]), savingFeedback: false,
    canRecordFeedback: false, autostart: false, onAutostart: vi.fn(), onPersonalCap: vi.fn(),
  };
}
it("switches peers in the same panel and keeps range controls outside scrolling content", () => {
  const { container } = render(<TrayPanel {...props()} />);
  fireEvent.click(screen.getByRole("button", { name: "Statistics" }));
  const sidebar = screen.getByLabelText("Statistics date range");
  const main = screen.getByRole("main");
  expect(main.contains(sidebar)).toBe(false);
  const first = screen.getByTestId("usage-range").textContent;
  fireEvent.click(screen.getByRole("button", { name: "90 days" }));
  expect(screen.getByTestId("usage-range").textContent).not.toBe(first);
  fireEvent.click(screen.getByRole("button", { name: "Members & devices" }));
  expect(screen.getByText("Member editor")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Calendar" }));
  expect(screen.getByRole("button", { name: "Day" })).toBeInTheDocument();
  expect(container.querySelectorAll(".tray-panel")).toHaveLength(1);
});
it("saves tray presentation and English text choices through canonical preferences", () => {
  const fixture = props(); render(<TrayPanel {...fixture} />);
  fireEvent.click(screen.getByRole("button", { name: "Settings" }));
  fireEvent.change(screen.getByLabelText("Available today display"), { target: { value: "bar" } });
  expect(fixture.onPreferences).toHaveBeenCalledWith(expect.objectContaining({ trayMode: "bar" }));
  fireEvent.click(screen.getByLabelText("Tray text in English"));
  expect(fixture.onPreferences).toHaveBeenCalledWith(expect.objectContaining({ trayEnglish: true, language: "en" }));
  expect(screen.getByText("Cloud settings")).toBeInTheDocument();
});
it("starts a newly selected page at the top without resetting the active page on refresh", () => {
  const fixture = props();
  const { rerender } = render(<TrayPanel {...fixture} />);
  fireEvent.click(screen.getByRole("button", { name: "Settings" }));
  const main = screen.getByRole("main");
  main.scrollTop = 300;
  rerender(<TrayPanel {...fixture} now={new Date(now.getTime() + 60_000)} />);
  expect(main.scrollTop).toBe(300);
  fireEvent.click(screen.getByRole("button", { name: "Calendar" }));
  expect(main.scrollTop).toBe(0);
  main.scrollTop = 100;
  fireEvent.click(screen.getByRole("button", { name: "Statistics" }));
  expect(main.scrollTop).toBe(0);
});
it("keeps unavailable allowance unknown and hides an absent confirmed reset", () => {
  render(<TrayPanel {...props()} />);
  expect(screen.queryByText("Codex reset announcement")).not.toBeInTheDocument();
  expect(screen.getByText(/unavailable values are not zero/)).toBeInTheDocument();
});
it("only accepts a fresh future dated announcement for the homepage", () => {
  const forecast: ResetForecast = { score: 0, windowHours: 24, fetchedAt: now.toISOString(), resetAnnounced: true,
    resetAt: new Date(now.getTime() + 3_600_000).toISOString(), sourceUrl: "https://codex-resets.com/" };
  expect(confirmedReset(forecast, now)).not.toBeNull();
  expect(confirmedReset({ ...forecast, resetAnnounced: false }, now)).toBeNull();
  expect(confirmedReset({ ...forecast, fetchedAt: new Date(now.getTime() - 600_000).toISOString() }, now)).toBeNull();
  expect(confirmedReset({ ...forecast, resetAt: now.toISOString() }, now)).toBeNull();
});
