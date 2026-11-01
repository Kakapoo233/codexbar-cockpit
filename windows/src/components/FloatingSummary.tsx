import { ArrowsOutSimple, GearSix, Minus } from "@phosphor-icons/react";
import type { PointerEvent } from "react";
import type { CockpitDailyPlanStatus } from "../lib/cockpitDailyPlan";
import type { ProviderSnapshot, WidgetPreferences } from "../types";
import "./FloatingSummary.css";

export interface FloatingSummaryProps {
  preferences: WidgetPreferences;
  snapshots: ProviderSnapshot[];
  plan: CockpitDailyPlanStatus;
  startupReady: boolean;
  refreshing: boolean;
  error: string | null;
  onOpen: (page: "usage" | "settings") => void;
  onHide: () => void;
  onDrag: () => void;
  onRefresh: () => void;
}

function quota(value: number | null | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100 ? value : null;
}

function formatPercent(value: number | null, zh: boolean, approximate = false): string {
  return value === null ? "—" : `${approximate ? "≈" : ""}${value.toLocaleString(zh ? "zh-CN" : "en-US", { maximumFractionDigits: 1 })}%`;
}

/** The floating surface receives the same scoped aggregates as the full panel; it never collects data. */
export function FloatingSummary(props: FloatingSummaryProps) {
  const { preferences, plan } = props;
  const zh = preferences.language !== "en";
  const enabled = (preferences.enabledProviders ?? ["codex"]).includes("codex") && !preferences.hiddenProviders.includes("codex");
  const codex = enabled ? props.snapshots.find(snapshot => snapshot.provider === "codex") : undefined;
  const usable = props.startupReady && codex && (codex.status === "ok" || codex.status === "stale");
  const stale = usable && codex.status === "stale";
  const short = usable ? quota(codex.shortWindow?.remainingPercent) : null;
  const weekly = usable ? quota(codex.weeklyWindow?.remainingPercent) : null;
  const remaining = usable ? quota(plan.remainingDailyBudgetPercent) : null;
  const weeklyEquivalent = usable && typeof plan.remainingSuggestedPercent === "number" && Number.isFinite(plan.remainingSuggestedPercent)
    && plan.remainingSuggestedPercent >= 0 ? plan.remainingSuggestedPercent : null;
  const recommendation = usable && typeof plan.suggestedPercent === "number" && Number.isFinite(plan.suggestedPercent)
    && plan.suggestedPercent >= 0 ? plan.suggestedPercent : null;
  const approximate = Boolean(stale || plan.isStale);
  const bound = plan.coverage !== "complete" ? "≤" : "";
  const remainingDescription = remaining === null
    ? zh ? "今日还能用：暂无数据" : "Available today: unavailable"
    : zh ? `今日还能用：${bound}${formatPercent(remaining, zh)}，占今日分配；相当于周额度 ${bound}${formatPercent(weeklyEquivalent, zh)}${approximate ? "，数据可能陈旧" : ""}`
      : `Available today: ${bound}${formatPercent(remaining, zh)} of today's allocation; weekly equivalent ${bound}${formatPercent(weeklyEquivalent, zh)}${approximate ? "; data may be stale" : ""}`;
  const status = !props.startupReady ? zh ? "加载中" : "Loading"
    : props.refreshing ? zh ? "刷新中" : "Refreshing"
      : props.error ? zh ? "需要刷新" : "Needs attention"
        : !enabled ? zh ? "已隐藏" : "Hidden"
          : !usable ? zh ? "暂无数据" : "Unavailable"
            : approximate ? zh ? "较早快照" : "Earlier snapshot" : zh ? "已更新" : "Updated";
  const mode = preferences.trayMode ?? "circle";
  const drag = (event: PointerEvent<HTMLElement>) => {
    if (event.button !== 0 || event.isPrimary === false || (event.target as Element).closest("button")) return;
    props.onDrag();
  };

  return <section className="floating-summary" aria-label={zh ? "额度悬浮窗" : "Floating usage summary"}>
    <header className="floating-summary-header" onPointerDown={drag} title={zh ? "拖动以移动悬浮窗" : "Drag to move the floating window"}>
      <div className="floating-summary-brand"><span className={`floating-summary-status${props.error || !usable ? " is-unavailable" : approximate ? " is-stale" : ""}`} role="img" aria-label={status} title={status} /><strong>CODEX</strong></div>
      <div className="floating-summary-actions">
        <button type="button" aria-label={zh ? "设置" : "Settings"} title={zh ? "设置" : "Settings"} onClick={() => props.onOpen("settings")}><GearSix /></button>
        <button type="button" aria-label={zh ? "打开完整面板" : "Open full panel"} title={zh ? "打开完整面板" : "Open full panel"} onClick={() => props.onOpen("usage")}><ArrowsOutSimple /></button>
        <button type="button" aria-label={zh ? "隐藏悬浮窗" : "Hide floating window"} title={zh ? "隐藏到系统托盘" : "Hide in the system tray"} onClick={props.onHide}><Minus /></button>
      </div>
    </header>
    <div className="floating-summary-values">
      <div className="floating-summary-metric" title={zh ? "官方短期剩余额度" : "Official short-term remaining quota"}><span>{zh ? "短期剩余" : "Short term"}</span><strong>{formatPercent(short, zh, Boolean(stale))}</strong></div>
      <div className="floating-summary-metric" title={zh ? "官方周额度剩余" : "Official weekly remaining quota"}><span>{zh ? "周额度" : "Weekly"}</span><strong>{formatPercent(weekly, zh, Boolean(stale))}</strong></div>
      <div className="floating-summary-metric floating-summary-today" title={remainingDescription}>
        <span>{zh ? "今日可用" : "T"}</span>
        {mode === "percent" ? <strong aria-label={remainingDescription}>{formatPercent(remaining, zh, approximate)}</strong>
          : <div className={`floating-summary-meter is-${mode}${remaining === null ? " is-unknown" : ""}`} role="img" aria-label={remainingDescription} data-state={remaining === null ? "unknown" : "known"}>
            <span className="floating-summary-meter-fill" aria-hidden="true" style={remaining === null ? undefined : mode === "bar" ? { width: `${remaining}%` } : { height: `${remaining}%` }} />
            <strong aria-hidden="true">{formatPercent(mode === "circle" && remaining !== null ? Math.round(remaining) : remaining, zh, approximate)}</strong>
          </div>}
      </div>
    </div>
    <footer className="floating-summary-footer">
      <span title={zh ? "全天建议，占每周总额度" : "Full-day recommendation, as a share of weekly quota"}>{zh ? "建议" : "T"} {formatPercent(recommendation, zh, approximate || plan.suggestionIsPartial)}<span className="floating-summary-footer-unit">{zh ? " · 周额度" : " recommended / week"}</span></span>
      {props.error && <button type="button" disabled={props.refreshing} onClick={props.onRefresh}>{zh ? "重试" : "Retry"}</button>}
      {!props.error && !usable && <button type="button" onClick={() => props.onOpen("usage")}>{zh ? "查看" : "Details"}</button>}
    </footer>
  </section>;
}
