// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
const native = vi.hoisted(() => ({ active: false, invoke: vi.fn(), listen: vi.fn() }));
vi.mock("./bridge", () => ({ isTauri: () => native.active }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: native.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ listen: native.listen }));
beforeEach(() => { vi.resetModules(); vi.clearAllMocks(); native.active = false; window.history.replaceState({}, "", "/?synthetic-preview=1&surface=compact"); });
afterEach(() => vi.restoreAllMocks());

it("previews compact/details transitions without invoking native commands or remounting a collector", async () => {
  const bridge = await import("./panelPresentation");
  const received = vi.fn();
  const stop = await bridge.listenPanelPresentation(received);
  expect(await bridge.getPanelPresentation()).toMatchObject({ displayMode: "floating", surface: "compact" });
  await bridge.openFullPanel("settings");
  expect(received).toHaveBeenLastCalledWith({ displayMode: "floating", surface: "panel", targetPage: "settings" });
  // Font/theme updates in Settings must not collapse an already open panel.
  bridge.applyPreviewDisplayMode("floating");
  expect((await bridge.getPanelPresentation()).surface).toBe("panel");
  await bridge.compactPanel();
  expect((await bridge.getPanelPresentation()).surface).toBe("compact");
  await bridge.beginFloatingDrag(); await bridge.hidePanel();
  expect(native.invoke).not.toHaveBeenCalled();
  stop(); const count = received.mock.calls.length;
  await bridge.openFullPanel();
  expect(received).toHaveBeenCalledTimes(count);
});
it("sends native window commands with a typed target page", async () => {
  native.active = true;
  native.invoke.mockResolvedValue({ displayMode: "floating", surface: "panel", targetPage: "settings" });
  const bridge = await import("./panelPresentation");
  expect(await bridge.getPanelPresentation()).toMatchObject({ targetPage: "settings" });
  await bridge.openFullPanel("settings"); await bridge.compactPanel(); await bridge.beginFloatingDrag(); await bridge.hidePanel();
  expect(native.invoke.mock.calls.map(call => call[0])).toEqual(["get_panel_presentation", "show_full_panel", "compact_panel", "begin_floating_drag", "hide_panel"]);
  expect(native.invoke).toHaveBeenCalledWith("show_full_panel", { targetPage: "settings" });
});
it("ignores invalid presentation events and rejects malformed getter results", async () => {
  native.active = true;
  const stop = vi.fn(); native.listen.mockResolvedValue(stop);
  const bridge = await import("./panelPresentation");
  const receive = vi.fn(); const unsubscribe = await bridge.listenPanelPresentation(receive);
  const handler = native.listen.mock.calls[0][1];
  handler({ payload: { displayMode: "floating", surface: "panel", targetPage: "external" } });
  expect(receive).not.toHaveBeenCalled();
  handler({ payload: { displayMode: "floating", surface: "compact" } });
  expect(receive).toHaveBeenCalledOnce(); unsubscribe(); expect(stop).toHaveBeenCalledOnce();
  native.invoke.mockResolvedValue({ displayMode: "floating", surface: "wrong" });
  await expect(bridge.getPanelPresentation()).rejects.toThrow("Invalid panel presentation");
});
