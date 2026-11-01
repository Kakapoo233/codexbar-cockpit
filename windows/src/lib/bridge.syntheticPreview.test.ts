import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { DEFAULT_WIDGET_PREFERENCES } from "./preferences";
import { EMPTY_RUNTIME_STATE } from "./activity";
import { fetchSnapshots, getPreferences, getRuntimeState, isSyntheticPreview, isTauri, openExternalUrl, updatePreferences, updateRuntimeState } from "./bridge";

const native = vi.hoisted(() => ({ invoke: vi.fn(), openUrl: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: native.invoke }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: native.openUrl }));
beforeEach(() => vi.clearAllMocks());
afterEach(() => vi.unstubAllGlobals());

it("uses synthetic reads and no native writes in an explicitly requested native preview", async () => {
  const open = vi.fn();
  vi.stubGlobal("window", { __TAURI_INTERNALS__: {}, location: { search: "?synthetic-preview=1" }, open });
  expect(isSyntheticPreview()).toBe(true);
  expect(isTauri()).toBe(false);
  expect(await getPreferences()).toEqual(DEFAULT_WIDGET_PREFERENCES);
  expect(await getRuntimeState()).toEqual(EMPTY_RUNTIME_STATE);
  expect((await fetchSnapshots()).find(snapshot => snapshot.provider === "codex")?.plan).toBe("PRO");
  await updatePreferences({ ...DEFAULT_WIDGET_PREFERENCES, trayEnglish: true });
  await updateRuntimeState(EMPTY_RUNTIME_STATE);
  await openExternalUrl("https://example.com/");
  expect(native.invoke).not.toHaveBeenCalled();
  expect(native.openUrl).not.toHaveBeenCalled();
  expect(open).not.toHaveBeenCalled();
});

it.each(["", "?preview=1", "?synthetic-preview=0", "?synthetic-preview=true", "?other=1"])(
  "retains native mode for ordinary or ambiguous preview parameters: %s", search => {
    vi.stubGlobal("window", { __TAURI_INTERNALS__: {}, location: { search } });
    expect(isSyntheticPreview()).toBe(false);
    expect(isTauri()).toBe(true);
  },
);
