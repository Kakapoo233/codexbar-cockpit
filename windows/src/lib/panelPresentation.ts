import { isTauri } from "./bridge";

export type PanelPage = "usage" | "settings";
export interface PanelPresentation {
  displayMode: "tray" | "floating";
  surface: "compact" | "panel";
  targetPage?: PanelPage | null;
}
const previewEvent = "cockpit-preview-presentation";
let preview: PanelPresentation | null = null;

function previewState(): PanelPresentation {
  if (!preview) {
    const compact = new URLSearchParams(window.location?.search ?? "").get("surface") === "compact";
    preview = { displayMode: compact ? "floating" : "tray", surface: compact ? "compact" : "panel" };
  }
  return { ...preview };
}
function publishPreview(value: PanelPresentation) {
  preview = value;
  window.dispatchEvent(new CustomEvent(previewEvent, { detail: { ...value } }));
}
function valid(value: unknown): value is PanelPresentation {
  if (!value || typeof value !== "object") return false;
  const p = value as PanelPresentation;
  return (p.displayMode === "tray" || p.displayMode === "floating")
    && (p.surface === "compact" || p.surface === "panel")
    && (p.targetPage == null || p.targetPage === "usage" || p.targetPage === "settings");
}
export async function getPanelPresentation(): Promise<PanelPresentation> {
  if (!isTauri()) return previewState();
  const { invoke } = await import("@tauri-apps/api/core");
  const value = await invoke<PanelPresentation>("get_panel_presentation");
  if (!valid(value)) throw new Error("Invalid panel presentation");
  return value;
}
export async function listenPanelPresentation(handler: (value: PanelPresentation) => void): Promise<() => void> {
  if (!isTauri()) {
    const listener = (event: Event) => {
      const value = (event as CustomEvent<unknown>).detail;
      if (valid(value)) handler(value);
    };
    window.addEventListener(previewEvent, listener);
    return () => window.removeEventListener(previewEvent, listener);
  }
  const { listen } = await import("@tauri-apps/api/event");
  return listen<PanelPresentation>("panel-presentation-changed", event => {
    if (valid(event.payload)) handler(event.payload);
  });
}
export function applyPreviewDisplayMode(displayMode: "tray" | "floating") {
  if (!isTauri() && previewState().displayMode !== displayMode) publishPreview({ displayMode, surface: displayMode === "floating" ? "compact" : "panel", targetPage: "settings" });
}
export async function openFullPanel(targetPage: PanelPage = "usage"): Promise<void> {
  if (!isTauri()) { publishPreview({ ...previewState(), surface: "panel", targetPage }); return; }
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("show_full_panel", { targetPage });
}
export async function compactPanel(): Promise<void> {
  if (!isTauri()) { publishPreview({ ...previewState(), surface: "compact", targetPage: null }); return; }
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("compact_panel");
}
export async function hidePanel(): Promise<void> {
  if (!isTauri()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("hide_panel");
}
export async function beginFloatingDrag(): Promise<void> {
  if (!isTauri()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("begin_floating_drag");
}
