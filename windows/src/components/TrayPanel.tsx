import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { ArrowClockwise, GearSix, X } from "@phosphor-icons/react";
import { isTauri, openExternalUrl } from "../lib/bridge";
import type { CockpitDailyPlanStatus, CockpitQuotaObservation } from "../lib/cockpitDailyPlan";
import type { AppDiagnostics, CodexDailyUsage, ComfortCode, ComfortFeedbackRecord, PersonalizedComfortCurve, ProviderSnapshot, ResetForecast, WidgetPreferences } from "../types";
import type { TokeiUsage } from "../lib/tokeiUsage";
import { calendarDate, localDateKey as reportingDateKey } from "../lib/usageDay";
import { DEFAULT_PROVIDER_ORDER } from "../lib/providers";
import { type UsageDateRange } from "../lib/usageCalendar";
import type { CockpitRecommendationPace } from "../lib/cockpitRecommendationPace";
import { RecommendationPace } from "./RecommendationPace";
import { CodexUsagePanel } from "./CodexUsagePanel";
import { ComfortHistoryCalendar } from "./ComfortHistoryCalendar";
import { ComfortCurvePanel } from "./ComfortCurvePanel";
import { TeamMemberSettings } from "./TeamMemberSettings";
import { CloudSyncSettings } from "./CloudSyncSettings";
import { LocalUsageSourceSettings } from "./LocalUsageSourceSettings";
import "./TrayPanel.css";

type Page = "usage" | "statistics" | "calendar" | "members" | "settings";
type Range = "7d" | "30d" | "90d" | "month" | "all";
interface Props {
  pageRequest?: { page: "usage" | "settings"; id: number };
  pace?: CockpitRecommendationPace | null;
  preferences: WidgetPreferences; onPreferences: (value: WidgetPreferences) => void;
  snapshots: ProviderSnapshot[]; plan: CockpitDailyPlanStatus; history: CockpitQuotaObservation[];
  forecast: ResetForecast | null; now: Date; usage: TokeiUsage | null; usageError: boolean;
  onUsageRefresh: () => Promise<unknown>; diagnostics: AppDiagnostics | null; startupReady: boolean;
  settingsWritable: boolean; error: string | null; onDismissError: () => void; refreshing: boolean;
  onRefresh: () => void; onHide: () => void; onFeedback: (date: string, value: ComfortCode) => void;
  feedback: ComfortFeedbackRecord[]; dailyUsage: CodexDailyUsage[]; curve: PersonalizedComfortCurve;
  savingFeedback: boolean; canRecordFeedback: boolean; autostart: boolean; onAutostart: (enabled: boolean) => void;
  onPersonalCap: (value: number | null) => void;
}

/** Only a fresh dated announcement may appear as a confirmed countdown. */
export function confirmedReset(forecast: ResetForecast | null, now: Date): Date | null {
  if (!forecast?.resetAnnounced || !forecast.resetAt) return null;
  const fetched = Date.parse(forecast.fetchedAt), reset = Date.parse(forecast.resetAt), current = now.getTime();
  return Number.isFinite(fetched) && Number.isFinite(reset) && fetched <= current + 300_000
    && current - fetched < 600_000 && reset > current ? new Date(reset) : null;
}
function countdown(date: Date, now: Date, zh: boolean) {
  const minutes = Math.max(1, Math.ceil((date.getTime() - now.getTime()) / 60_000));
  const days = Math.floor(minutes / 1440), hours = Math.floor(minutes % 1440 / 60), rest = minutes % 60;
  return zh ? `${days ? `${days}天 ` : ""}${hours}小时 ${rest}分` : `${days ? `${days}d ` : ""}${hours}h ${rest}m`;
}
function rangeFor(range: Range, now: Date): UsageDateRange | null {
  if (range === "all") return null;
  const today = reportingDateKey(now);
  const [year, month, day] = today.split("-").map(Number);
  const start = range === "month" ? calendarDate(year, month - 1, 1)
    : calendarDate(year, month - 1, day - ({ "7d": 6, "30d": 29, "90d": 89 }[range]));
  return { start: reportingDateKey(start), end: today, scale: range === "month" ? "month" : "day" };
}
function percent(value: number | null | undefined, prefix = "") {
  return value === null || value === undefined || !Number.isFinite(value) ? "—" : `${prefix}${value.toLocaleString(undefined, { maximumFractionDigits: 1 })}%`;
}
function WindowMeter({ label, value }: { label: string; value: number | null }) {
  return <div className="tray-window-meter"><span>{label}<strong>{percent(value)}</strong></span>
    <div className="tray-meter-track" role="img" aria-label={`${label} ${percent(value)}`}>
      {value !== null && <i style={{ width: `${Math.max(0, Math.min(100, value))}%` }} />}
    </div></div>;
}
function QuotaHistory({ history, range, zh }: { history: CockpitQuotaObservation[]; range: UsageDateRange | null; zh: boolean }) {
  const rows = history.filter(row => !range || reportingDateKey(new Date(row.capturedAt)) >= range.start && reportingDateKey(new Date(row.capturedAt)) <= range.end);
  const start = range ? Date.parse(`${range.start}T00:00:00+08:00`) : Date.parse(rows[0]?.capturedAt ?? "");
  const end = range ? Date.parse(`${range.end}T23:59:59+08:00`) : Date.parse(rows.at(-1)?.capturedAt ?? "");
  const x = (value: string) => 30 + (Date.parse(value) - start) / Math.max(1, end - start) * 580;
  const paths: string[] = [];
  let active: string[] = [];
  rows.forEach((row, index) => {
    const previous = rows[index - 1];
    if (previous && (previous.resetsAt !== row.resetsAt || Date.parse(row.capturedAt) - Date.parse(previous.capturedAt) > 1_800_000)) {
      paths.push(active.join(" ")); active = [];
    }
    active.push(`${active.length ? "L" : "M"}${x(row.capturedAt).toFixed(1)},${(125 - row.remainingPercent).toFixed(1)}`);
  });
  if (active.length) paths.push(active.join(" "));
  return <section className="tray-card tray-quota-history" aria-label={zh ? "额度历史" : "Quota history"}>
    <h2>{zh ? "套餐额度历史" : "Plan quota history"}</h2>
    {rows.length ? <><svg viewBox="0 0 640 160" role="img" aria-label={zh ? "所选日期内的已观测剩余额度" : "Observed remaining quota in the selected dates"}>
      <path d="M30 25H610 M30 75H610 M30 125H610" className="tray-chart-grid" />
      <text x="0" y="29">100%</text><text x="8" y="129">0%</text>
      {paths.map((path, index) => <path key={index} d={path} className="tray-chart-line" />)}
      {rows.length < 60 && rows.map((row, index) => <circle key={index} cx={x(row.capturedAt)} cy={125 - row.remainingPercent} r="2.5" className="tray-chart-dot" />)}
    </svg><div className="tray-chart-axis"><span>{range?.start ?? reportingDateKey(new Date(rows[0].capturedAt))}</span><span>{range?.end ?? reportingDateKey(new Date(rows.at(-1)!.capturedAt))}</span></div>
    <small>{zh ? `${rows.length} 次观测；缺失时段和重置之间不连线。` : `${rows.length} observations; gaps and resets remain disconnected.`}</small></>
      : <p className="usage-note">{zh ? "所选时间范围暂无额度观测，后台采集后会逐步积累。" : "No quota observations in this range yet. History accumulates while the app runs."}</p>}
  </section>;
}

export function TrayPanel(props: Props) {
  const { preferences, onPreferences, plan, now, forecast } = props;
  const zh = preferences.language !== "en";
  const [page, setPage] = useState<Page>(props.pageRequest?.page ?? "usage");
  const [range, setRange] = useState<Range>("7d");
  const contentRef = useRef<HTMLElement>(null);
  useLayoutEffect(() => {
    // Pages share a scroll container, but a previous page's offset must not hide the next header.
    if (contentRef.current) contentRef.current.scrollTop = 0;
  }, [page]);
  const dateRange = useMemo(() => rangeFor(range, now), [range, now]);
  const reset = confirmedReset(forecast, now);
  const partial = plan.coverage !== "complete";
  const qualifier = `${plan.isStale ? "≈" : ""}${partial ? "≤" : ""}`;
  const patch = (value: Partial<WidgetPreferences>) => onPreferences({ ...preferences, ...value });
  useEffect(() => { if (props.pageRequest) setPage(props.pageRequest.page); }, [props.pageRequest]);
  return <div className="tray-panel" onKeyDown={event => { if (event.key === "Escape" && !(event.target instanceof HTMLSelectElement)) props.onHide(); }}>
    <header className="tray-panel-header">
      <div><strong>CodexBar Cockpit</strong><small>{isTauri() ? "Windows" : zh ? "合成数据预览" : "Synthetic preview"}</small></div>
      <div className="tray-header-actions"><button type="button" disabled={props.refreshing || !props.startupReady} onClick={props.onRefresh} title={zh ? "刷新额度与本机用量" : "Refresh quota and local usage"} aria-label={zh ? "刷新" : "Refresh"}><ArrowClockwise /></button>
        <button type="button" onClick={() => setPage("settings")} title={zh ? "设置" : "Settings"} aria-label={zh ? "设置" : "Settings"}><GearSix /></button>
        <button type="button" onClick={props.onHide} title={preferences.displayMode === "floating" ? (zh ? "返回悬浮窗" : "Back to floating summary") : (zh ? "收起到系统托盘" : "Hide in system tray")} aria-label={zh ? "收起" : "Hide"}><X /></button></div>
    </header>
    <nav className="tray-page-tabs" aria-label={zh ? "页面" : "Pages"}>
      {(["usage", "statistics", "calendar", "members"] as const).map(value => <button key={value} type="button" aria-pressed={page === value} onClick={() => setPage(value)}>{({ usage: zh ? "用量" : "Usage", statistics: zh ? "用量统计" : "Statistics", calendar: zh ? "日历" : "Calendar", members: zh ? "组员与设备" : "Members & devices" })[value]}</button>)}
    </nav>
    {props.error && <div className="tray-error" role="alert"><span>{props.error}</span><button type="button" onClick={props.onDismissError}>{zh ? "关闭提示" : "Dismiss"}</button></div>}
    <div className="tray-page-layout">
      {page === "statistics" && <aside className="tray-date-sidebar" aria-label={zh ? "统计时间范围" : "Statistics date range"}>
        {(["7d", "30d", "90d", "month", "all"] as const).map(value => <button key={value} type="button" aria-pressed={range === value} onClick={() => setRange(value)}>{({ "7d": zh ? "7 天" : "7 days", "30d": zh ? "30 天" : "30 days", "90d": zh ? "90 天" : "90 days", month: zh ? "本月至今" : "This month", all: zh ? "全部" : "All" })[value]}</button>)}
      </aside>}
      <main ref={contentRef} className="tray-page-content" aria-label={({ usage: zh ? "用量页面" : "Usage page", statistics: zh ? "用量统计页面" : "Statistics page", calendar: zh ? "日历页面" : "Calendar page", members: zh ? "组员与设备页面" : "Members & devices page", settings: zh ? "设置页面" : "Settings page" })[page]}>
        {(page === "usage" || page === "calendar") && (reset ? <section className="tray-reset-announcement" role="status"><strong>{zh ? "Codex 重置公告" : "Codex reset announcement"}</strong><span>{reset.toLocaleString(zh ? "zh-CN" : "en-US")} · {countdown(reset, now, zh)}</span></section>
          : page === "calendar" ? <section className="tray-reset-announcement"><strong>{zh ? "Codex 重置公告" : "Codex reset announcements"}</strong><span>{zh ? "暂无新鲜、已确定日期的重置公告。" : "No fresh confirmed reset date."}</span>{forecast?.historyResetDates?.length ? <details><summary>{zh ? "已同步重置历史" : "Synced reset history"}</summary><p>{forecast.historyResetDates.join(" · ")}</p></details> : null}</section> : null)}
        {page === "usage" && <>
          <section className="tray-card tray-advice" aria-label={zh ? "每日使用建议" : "Daily advice"}>
            <h2>{zh ? "每日使用建议" : "Daily advice"}</h2>
            <div className="tray-advice-values"><div><span>{zh ? "全天建议" : "Full-day recommendation"}</span><strong>{percent(plan.suggestedPercent, plan.suggestionIsPartial ? "≈" : "")}</strong><small>{zh ? "占周额度" : "of weekly quota"}</small></div>
              <div><span>{zh ? "今日还能用" : "Available today"}</span><strong>{percent(plan.remainingDailyBudgetPercent, qualifier)}</strong><small>{zh ? `今日分配为 100% · 周额度 ${percent(plan.remainingSuggestedPercent, qualifier)}` : `Daily allocation = 100% · Weekly ${percent(plan.remainingSuggestedPercent, qualifier)}`}</small></div>
              <div><span>{zh ? "舒适上限" : "Comfort limit"}</span><strong>{percent(plan.comfortAdvice?.softCapPercent)}</strong><small>{zh ? "占周额度" : "of weekly quota"}</small></div></div>
            <RecommendationPace pace={props.pace ?? null} language={preferences.language} />
            <label className="tray-cap-control"><span>{zh ? "个人上限（占周额度）" : "Personal cap (weekly quota)"}</span><input type="number" min="0" max="100" step="0.1" value={plan.manualCapPercent ?? ""} placeholder={zh ? "自动建议" : "Automatic"} disabled={!props.canRecordFeedback || !props.settingsWritable} onChange={event => props.onPersonalCap(event.target.value === "" ? null : Number(event.target.value))} /></label>
            <button type="button" className="usage-text-button" disabled={plan.manualCapPercent === null} onClick={() => props.onPersonalCap(null)}>{zh ? "恢复自动建议" : "Restore automatic advice"}</button>
            {plan.remainingDailyBudgetPercent === null && <p className="usage-note">{zh ? "需要可识别账户的官方周额度观测；暂无数据不会当作 0%。" : "Official weekly observations with an identified account are required; unavailable values are not zero."}</p>}
            {partial && plan.remainingDailyBudgetPercent !== null && <p className="usage-note">{zh ? "≤ 表示观测不完整，今日实际可用额度可能更少。" : "≤ marks incomplete observations; actual available allowance may be lower."}</p>}
            {plan.planningResetWindow && <small>{zh ? "计算窗口" : "Planning horizon"} · {new Date(plan.planningResetWindow.resetsAt).toLocaleString()} · {plan.planningResetWindow.source}</small>}
          </section>
          <div className="tray-provider-grid">{props.snapshots.filter(value => !preferences.hiddenProviders.includes(value.provider)).map(snapshot => <section key={snapshot.provider} className="tray-card" aria-label={`${snapshot.displayName} ${zh ? "额度" : "quota"}`}><h2>{snapshot.displayName}<small>{snapshot.plan ?? ""}</small></h2><WindowMeter label={zh ? "短期剩余" : "Short-term remaining"} value={snapshot.shortWindow?.remainingPercent ?? null} /><WindowMeter label={zh ? "周额度剩余" : "Weekly remaining"} value={snapshot.weeklyWindow?.remainingPercent ?? null} /><small>{snapshot.status}{snapshot.message ? ` · ${snapshot.message}` : ""}</small></section>)}</div>
          {!props.snapshots.length && <p role="status">{props.startupReady ? zh ? "暂无额度数据，请检查登录状态与本机数据目录。" : "No quota data. Check sign-in and local data sources." : zh ? "正在加载…" : "Loading…"}</p>}
        </>}
        {page === "statistics" && <><QuotaHistory history={props.history} range={dateRange} zh={zh} /><CodexUsagePanel zh={zh} initialUsage={props.usage} onOpenSettings={() => setPage("settings")} externalRange={dateRange} fixedRange /></>}
        {page === "calendar" && <><ComfortHistoryCalendar records={props.feedback} dailyUsageHistory={props.dailyUsage} language={preferences.language} onChange={props.onFeedback} saving={props.savingFeedback || !props.canRecordFeedback} personalLocalDay /><ComfortCurvePanel curve={props.curve} language={preferences.language} /></>}
        {page === "members" && <><p className="usage-note">{zh ? "管理人员与设备归属。云服务地址和连接凭据在设置中配置；Windows 活动上传正在适配，当前不会发送活动快照。" : "Manage members and device assignment. Configure your cloud service in Settings. Windows activity upload is pending adaptation; activity snapshots are not sent."}</p><TeamMemberSettings usage={props.usage} loadingError={props.usageError} preferences={preferences} zh={zh} onPreferences={onPreferences} onSaved={props.onUsageRefresh} /></>}
        {page === "settings" && <div className="tray-settings">
          <fieldset disabled={!props.settingsWritable}>
            <section className="tray-card"><h2>{zh ? "托盘与界面" : "Tray & appearance"}</h2>
              <label className="tray-setting-row"><span>{zh ? "显示方式" : "Display mode"}</span><select value={preferences.displayMode ?? "tray"} onChange={event => patch({ displayMode: event.target.value as WidgetPreferences["displayMode"] })}><option value="tray">{zh ? "托盘面板" : "Tray panel"}</option><option value="floating">{zh ? "简洁悬浮窗" : "Compact floating window"}</option></select></label>
              <label className="tray-setting-row tray-toggle-row"><span>{zh ? "悬浮窗置顶" : "Keep floating window on top"}</span><input type="checkbox" checked={preferences.alwaysOnTop} onChange={event => patch({ alwaysOnTop: event.target.checked })} /></label>
              <label className="tray-setting-row"><span>{zh ? "今日还能用显示形式" : "Available today display"}</span><select value={preferences.trayMode ?? "circle"} onChange={event => patch({ trayMode: event.target.value as WidgetPreferences["trayMode"] })} title={zh ? "按今日分配额度计算，支持数字、用量条和从下往上填充的圆形。" : "Remaining daily allocation shown as percentage, bar, or bottom-up filled circle."}><option value="percent">{zh ? "数字百分比" : "Percentage"}</option><option value="bar">{zh ? "用量条" : "Bar"}</option><option value="circle">{zh ? "圆形填充" : "Filled circle"}</option></select></label>
              <label className="tray-setting-row tray-toggle-row"><span>{zh ? "托盘文字使用英文" : "Tray text in English"}</span><input type="checkbox" checked={preferences.trayEnglish === true} onChange={event => patch({ trayEnglish: event.target.checked })} title={zh ? "仅托盘提示使用英文，展开面板保持当前语言。" : "Use English only for the tray tooltip; the panel keeps its selected language."} /></label>
              <label className="tray-setting-row"><span>{zh ? "语言" : "Language"}</span><select value={preferences.language} onChange={event => patch({ language: event.target.value as WidgetPreferences["language"] })}><option value="zh-CN">简体中文</option><option value="en">English</option></select></label>
              <label className="tray-setting-row"><span>{zh ? "外观" : "Appearance"}</span><select value={preferences.appearanceMode} onChange={event => patch({ appearanceMode: event.target.value as WidgetPreferences["appearanceMode"] })}><option value="system">{zh ? "跟随系统" : "System"}</option><option value="light">{zh ? "浅色" : "Light"}</option><option value="dark">{zh ? "深色" : "Dark"}</option></select></label>
              <label className="tray-setting-row"><span>{zh ? "字体大小" : "Text scale"}</span><span className="tray-setting-control"><input type="range" min="1" max="2" step="0.05" value={preferences.fontScale} onChange={event => patch({ fontScale: Number(event.target.value) })} /><output>{Math.round(preferences.fontScale * 100)}%</output></span></label>
              <label className="tray-setting-row tray-toggle-row"><span>{zh ? "登录时启动" : "Launch at login"}</span><input type="checkbox" checked={props.autostart} onChange={event => props.onAutostart(event.target.checked)} /></label>
            </section>
            <section className="tray-card"><h2>{zh ? "提供商" : "Providers"}</h2><div className="tray-provider-options">{DEFAULT_PROVIDER_ORDER.map(provider => <label key={provider}><input type="checkbox" checked={(preferences.enabledProviders ?? ["codex"]).includes(provider)} onChange={event => patch({ enabledProviders: event.target.checked ? [...(preferences.enabledProviders ?? ["codex"]), provider] : (preferences.enabledProviders ?? ["codex"]).filter(value => value !== provider), hiddenProviders: event.target.checked ? preferences.hiddenProviders.filter(value => value !== provider) : [...preferences.hiddenProviders, provider] })} />{provider}</label>)}</div><p className="usage-note">{zh ? "当前为 Cockpit 原生采集器支持的提供商；其余 CodexBar 提供商待逐项适配。" : "These providers use the ported Cockpit collectors. Additional CodexBar providers require individual adaptation."}</p></section>
          </fieldset>
          <LocalUsageSourceSettings zh={zh} onSaved={() => { props.onRefresh(); }} />
          <CloudSyncSettings usage={props.usage} zh={zh} onSynced={props.onUsageRefresh} />
          <section className="tray-card"><h2>{zh ? "关于" : "About"}</h2><strong>CodexBar Cockpit · Windows</strong><p>{props.diagnostics?.appVersion ?? "0.1.0-alpha.4"}</p><p>{zh ? "基于 CodexBar 与 Codex Cockpit 的独立开源整合。" : "An independent open-source integration of CodexBar and Codex Cockpit."}</p><button type="button" onClick={() => void openExternalUrl("https://github.com/Kakapoo233/codexbar-cockpit")}>{zh ? "开源项目" : "Project on GitHub"}</button><p className="usage-note">{zh ? "Windows 测试版：尚未完成全部提供商、多语言和跨设备同步验收。" : "Windows alpha: full provider, language and cross-device parity is not yet verified."}</p></section>
        </div>}
      </main>
    </div>
  </div>;
}
