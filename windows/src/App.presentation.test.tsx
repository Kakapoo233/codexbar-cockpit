// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { useState } from "react";
import { DEFAULT_WIDGET_PREFERENCES } from "./lib/preferences";
import { EMPTY_RUNTIME_STATE } from "./lib/activity";
import { localCalendarDay } from "./lib/cockpitDailyPlan";
import { COMFORT_CURVE_VERSION } from "./lib/comfortFeedback";
import type { CockpitRecommendationPace } from "./lib/cockpitRecommendationPace";
import type { ComfortFeedbackRecord, ProviderSnapshot } from "./types";
import type { PanelPresentation } from "./lib/panelPresentation";
import App from "./App";
const state = vi.hoisted(() => ({ receive: null as ((p: PanelPresentation) => void) | null,
  get: vi.fn(), fetch: vi.fn(), runtime: vi.fn(), saveRuntime: vi.fn(async (_value: unknown) => undefined), floating: vi.fn(), panel: vi.fn(), stop: vi.fn(), refreshUsage: vi.fn(async () => undefined) }));
vi.mock("./lib/bridge", () => ({
  isTauri: () => false,
  getPreferences: async () => ({ ...DEFAULT_WIDGET_PREFERENCES, displayMode: "floating" }),
  getRuntimeState: () => state.runtime(),
  getAppDiagnostics: async () => null, getAutostartEnabled: async () => false,
  fetchSnapshots: (...args: unknown[]) => state.fetch(...args), fetchCodexResetForecast: async () => null,
  updatePreferences: vi.fn(async () => undefined), updateRuntimeState: state.saveRuntime,
  setAutostartEnabled: async (v: boolean) => v, listenDesktopEvents: async () => () => undefined,
}));
vi.mock("./lib/useComfortUsage", () => ({ useComfortUsage: () => ({ data: null, error: false, refresh: state.refreshUsage }) }));
vi.mock("./lib/panelPresentation", () => ({
  getPanelPresentation: () => state.get(),
  listenPanelPresentation: async (receive: (p: PanelPresentation) => void) => { state.receive = receive; return state.stop; },
  openFullPanel: async (targetPage: "settings" | "usage") => state.receive?.({ displayMode: "floating", surface: "panel", targetPage }),
  compactPanel: async () => state.receive?.({ displayMode: "floating", surface: "compact" }),
  hidePanel: vi.fn(async () => undefined), beginFloatingDrag: vi.fn(async () => undefined), applyPreviewDisplayMode: vi.fn(),
}));
vi.mock("./components/FloatingSummary", () => ({ FloatingSummary: (p: {onOpen: (page: "settings") => void; pace?: CockpitRecommendationPace | null}) => {
  state.floating(p);
  return <button onClick={() => p.onOpen("settings")}>Floating settings</button>;
} }));
vi.mock("./components/TrayPanel", () => ({ TrayPanel: (p: {pageRequest?: {page: string}; onHide: () => void; pace?: CockpitRecommendationPace | null}) => {
  state.panel(p);
  const [draft, setDraft] = useState("");
  return <section aria-label="Full panel"><span>{p.pageRequest?.page}</span><input aria-label="Cloud draft" value={draft} onChange={event => setDraft(event.target.value)} /><button onClick={p.onHide}>Return to summary</button></section>;
} }));
beforeEach(() => {
  vi.clearAllMocks(); state.receive = null;
  state.get.mockResolvedValue({ displayMode: "floating", surface: "compact" });
  state.fetch.mockResolvedValue([]);
  state.runtime.mockResolvedValue(structuredClone(EMPTY_RUNTIME_STATE));
});
afterEach(cleanup);
it("opens Settings from the compact surface and reuses collection across both surfaces", async () => {
  const { unmount } = render(<App />);
  const settings = await screen.findByRole("button", { name: "Floating settings" });
  await waitFor(() => expect(state.fetch).toHaveBeenCalledOnce());
  fireEvent.click(settings);
  expect(await screen.findByRole("region", { name: "Full panel" })).toHaveTextContent("settings");
  fireEvent.change(screen.getByRole("textbox", { name: "Cloud draft" }), { target: { value: "https://example.workers.dev" } });
  fireEvent.click(screen.getByRole("button", { name: "Return to summary" }));
  expect(await screen.findByRole("button", { name: "Floating settings" })).toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: "Cloud draft" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Floating settings" }));
  expect(await screen.findByRole("textbox", { name: "Cloud draft" })).toHaveValue("https://example.workers.dev");
  expect(state.fetch).toHaveBeenCalledOnce();
  unmount(); expect(state.stop).toHaveBeenCalledOnce();
});
it("does not let an older initial getter overwrite a newer Settings presentation event", async () => {
  let resolve!: (p: PanelPresentation) => void;
  state.get.mockReturnValue(new Promise<PanelPresentation>(done => { resolve = done; }));
  render(<App />);
  await waitFor(() => expect(state.get).toHaveBeenCalledOnce());
  act(() => state.receive?.({ displayMode: "floating", surface: "panel", targetPage: "settings" }));
  expect(await screen.findByRole("region", { name: "Full panel" })).toHaveTextContent("settings");
  await act(async () => resolve({ displayMode: "floating", surface: "compact" }));
  expect(screen.getByRole("region", { name: "Full panel" })).toHaveTextContent("settings");
  expect(screen.queryByRole("button", { name: "Floating settings" })).not.toBeInTheDocument();
});

it("publishes one scoped daily recommendation pace to compact and retained full surfaces", async () => {
  const time = Date.now();
  const reset = new Date(time + 5 * 86400_000).toISOString();
  const snapshot: ProviderSnapshot = { provider: "codex", accountScope: "synthetic-local-owner", displayName: "Codex", plan: "Synthetic",
    status: "ok", updatedAt: new Date(time - 60_000).toISOString(), message: null, shortWindow: null, resetCredits: null,
    weeklyWindow: { remainingPercent: 50, resetsAt: reset, windowSeconds: 604800 } };
  state.fetch.mockResolvedValue([snapshot]);
  state.runtime.mockResolvedValue({ ...structuredClone(EMPTY_RUNTIME_STATE), cockpitQuotaObservations: [
    { providerID: "codex", accountID: snapshot.accountScope, capturedAt: new Date(time - 120_000).toISOString(), remainingPercent: 60, resetsAt: reset, coverage: "complete" },
    { providerID: "codex", accountID: snapshot.accountScope, capturedAt: snapshot.updatedAt, remainingPercent: 50, resetsAt: reset, coverage: "complete" },
  ] });
  render(<App />);
  await waitFor(() => expect(state.floating.mock.calls.at(-1)?.[0]?.pace).toEqual(expect.objectContaining({ observedUsedPercent: 10, isLowerBound: true })));
  const compactPace = state.floating.mock.calls.at(-1)![0].pace;
  expect(state.panel.mock.calls.at(-1)![0].pace).toBe(compactPace);
  fireEvent.click(screen.getByRole("button", { name: "Floating settings" }));
  expect(state.panel.mock.calls.at(-1)![0].pace).toBe(compactPace);
  expect(state.fetch).toHaveBeenCalledOnce();
});

it("changes or clears only the personal quota entry for the requested date, account and zone", async () => {
  const time = new Date();
  const { timeZoneIdentifier } = localCalendarDay(time);
  const entry: ComfortFeedbackRecord = { localDate: "2025-01-08", accountScope: "a".repeat(64), timeZoneIdentifier,
    observedAt: "2025-01-08T12:00:00Z", comfort: "comfortable", observedUsedPercent: 18,
    usageObservedAt: "2025-01-08T12:00:00Z", usageCoverage: "complete", usageSource: "official-snapshot",
    curveVersion: COMFORT_CURVE_VERSION };
  const otherRecords = [
    { ...entry, accountScope: "b".repeat(64) },
    { ...entry, timeZoneIdentifier: timeZoneIdentifier === "UTC" ? "Asia/Shanghai" : "UTC" },
    { ...entry, personId: "synthetic-team-member" },
    { ...entry, localDate: "2025-01-07" },
  ];
  const legacy = { ...entry, localDate: "2025-01-06", timeZoneIdentifier: undefined };
  const duplicate = { ...entry, timeZoneIdentifier: undefined, comfort: "overloaded" as const };
  state.runtime.mockResolvedValue({ ...structuredClone(EMPTY_RUNTIME_STATE), comfortFeedback: [entry, duplicate, ...otherRecords, legacy] });
  const snapshot: ProviderSnapshot = { provider: "codex", accountScope: entry.accountScope, displayName: "Codex", plan: "Synthetic",
    status: "ok", updatedAt: time.toISOString(), message: null, shortWindow: null, resetCredits: null, weeklyWindow: null };
  state.fetch.mockResolvedValue([snapshot]);
  render(<App />);
  const panel = () => state.panel.mock.calls.at(-1)![0];
  await waitFor(() => expect(panel().feedback).toEqual([entry, otherRecords[3], legacy]));

  await act(async () => { panel().onFeedback(entry.localDate, "idle"); });
  expect(state.saveRuntime).toHaveBeenLastCalledWith(expect.objectContaining({ comfortFeedback: [
    ...otherRecords, legacy, expect.objectContaining({ ...entry, comfort: "idle" }),
  ] }));
  await act(async () => { panel().onFeedback(entry.localDate, null); });
  expect(state.saveRuntime).toHaveBeenLastCalledWith(expect.objectContaining({ comfortFeedback: [...otherRecords, legacy] }));
  expect(panel().feedback).toEqual([otherRecords[3], legacy]);
  await act(async () => { panel().onFeedback(legacy.localDate, "idle"); });
  expect(state.saveRuntime).toHaveBeenLastCalledWith(expect.objectContaining({ comfortFeedback: [
    ...otherRecords, expect.objectContaining({ ...legacy, comfort: "idle", timeZoneIdentifier }),
  ] }));

  const futureDate = localCalendarDay(new Date(time.getTime() + 2 * 86_400_000)).localDateKey;
  await act(async () => { panel().onFeedback(futureDate, "overloaded"); });
  expect(state.saveRuntime).toHaveBeenCalledTimes(3);

  const oldOnFeedback = panel().onFeedback;
  await waitFor(() => expect(panel().refreshing).toBe(false));
  state.fetch.mockResolvedValue([{ ...snapshot, accountScope: otherRecords[0].accountScope }]);
  act(() => { panel().onRefresh(); });
  await waitFor(() => expect(panel().feedback).toEqual([otherRecords[0]]));
  await act(async () => { oldOnFeedback(legacy.localDate, "overloaded"); });
  expect(state.saveRuntime).toHaveBeenCalledTimes(3);
});
