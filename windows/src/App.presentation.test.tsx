// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { useState } from "react";
import { DEFAULT_WIDGET_PREFERENCES } from "./lib/preferences";
import { EMPTY_RUNTIME_STATE } from "./lib/activity";
import type { CockpitRecommendationPace } from "./lib/cockpitRecommendationPace";
import type { ProviderSnapshot } from "./types";
import type { PanelPresentation } from "./lib/panelPresentation";
import App from "./App";
const state = vi.hoisted(() => ({ receive: null as ((p: PanelPresentation) => void) | null,
  get: vi.fn(), fetch: vi.fn(), runtime: vi.fn(), floating: vi.fn(), panel: vi.fn(), stop: vi.fn(), refreshUsage: vi.fn(async () => undefined) }));
vi.mock("./lib/bridge", () => ({
  isTauri: () => false,
  getPreferences: async () => ({ ...DEFAULT_WIDGET_PREFERENCES, displayMode: "floating" }),
  getRuntimeState: () => state.runtime(),
  getAppDiagnostics: async () => null, getAutostartEnabled: async () => false,
  fetchSnapshots: (...args: unknown[]) => state.fetch(...args), fetchCodexResetForecast: async () => null,
  updatePreferences: vi.fn(async () => undefined), updateRuntimeState: vi.fn(async () => undefined),
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
