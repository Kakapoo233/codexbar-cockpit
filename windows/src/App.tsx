import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getAppDiagnostics, getAutostartEnabled, getPreferences, getRuntimeState, fetchSnapshots, fetchCodexResetForecast, isTauri, listenDesktopEvents, setAutostartEnabled, updatePreferences, updateRuntimeState } from "./lib/bridge";
import { DEFAULT_WIDGET_PREFERENCES, normalizeWidgetPreferences } from "./lib/preferences";
import { EMPTY_RUNTIME_STATE } from "./lib/activity";
import { resolveAppearanceMode, systemPrefersDark } from "./lib/appearance";
import { useComfortUsage } from "./lib/useComfortUsage";
import { createComfortFeedbackRecord, personalizeComfortCurve } from "./lib/comfortFeedback";
import { buildCockpitDailyPlan, cockpitResetSignal, localCalendarDay, type CockpitQuotaObservation } from "./lib/cockpitDailyPlan";
import { TrayPanel } from "./components/TrayPanel";
import { FloatingSummary } from "./components/FloatingSummary";
import { applyPreviewDisplayMode, beginFloatingDrag, compactPanel, getPanelPresentation, hidePanel, listenPanelPresentation, openFullPanel, type PanelPage, type PanelPresentation } from "./lib/panelPresentation";
import type { AppDiagnostics, CodexDailyUsage, ComfortCode, ProviderSnapshot, ResetForecast, RuntimeState, WidgetPreferences } from "./types";

/** Native collection stays in Rust. The React shell receives only typed quota/usage aggregates. */
export default function App() {
  const [preferences, setPreferences] = useState<WidgetPreferences>(DEFAULT_WIDGET_PREFERENCES);
  const [runtime, setRuntime] = useState<RuntimeState>(EMPTY_RUNTIME_STATE);
  const [snapshots, setSnapshots] = useState<ProviderSnapshot[]>([]);
  const [forecast, setForecast] = useState<ResetForecast | null>(null);
  const [diagnostics, setDiagnostics] = useState<AppDiagnostics | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [savingFeedback, setSavingFeedback] = useState(false);
  const [autostart, setAutostart] = useState(false);
  const [now, setNow] = useState(() => new Date());
  const [systemDark, setSystemDark] = useState(systemPrefersDark);
  const [surface, setSurface] = useState<"compact" | "panel">("panel");
  const [pageRequest, setPageRequest] = useState<{ page: PanelPage; id: number }>();
  const runtimeRef = useRef(runtime);
  const preferencesRef = useRef(preferences);
  const writable = useRef(false);
  const preferenceWritable = useRef(false);
  const alive = useRef(true);
  const refreshBusy = useRef(false);
  const feedbackBusy = useRef(false);
  const preferenceSequence = useRef(0);
  const { data: usage, error: usageError, refresh: refreshUsage } = useComfortUsage(ready);
  const language = preferences.language;
  const zh = language !== "en";
  const codex = snapshots.find(value => value.provider === "codex");
  const scope = codex?.accountScope ?? null;
  const today = localCalendarDay(now).localDateKey;

  useEffect(() => {
    let active = true;
    let revision = 0;
    let unsubscribe: (() => void) | undefined;
    const receive = (value: PanelPresentation) => {
      if (!active) return;
      revision += 1;
      setSurface(value.surface);
      if (value.targetPage) setPageRequest(previous => ({ page: value.targetPage!, id: (previous?.id ?? 0) + 1 }));
    };
    void listenPanelPresentation(receive).then(async stop => {
      if (!active) { stop(); return; }
      unsubscribe = stop;
      const expectedRevision = revision;
      const current = await getPanelPresentation();
      if (active && revision === expectedRevision) receive(current);
    }).catch(() => { if (active) setError("Window presentation is unavailable. Reopen the panel from the tray."); });
    return () => { active = false; unsubscribe?.(); };
  }, []);

  const commitRuntime = useCallback(async (next: RuntimeState) => {
    if (!writable.current) throw new Error("Saved data is unavailable; writing is paused to preserve it.");
    runtimeRef.current = next;
    setRuntime(next);
    await updateRuntimeState(next);
  }, []);

  const publishSnapshots = useCallback(async (values: ProviderSnapshot[]) => {
    if (!alive.current) return;
    setSnapshots(values);
    if (!writable.current) return;
    const current = runtimeRef.current;
    const additions: CockpitQuotaObservation[] = values.flatMap(snapshot => {
      const window = snapshot.weeklyWindow;
      if (!snapshot.accountScope || !window?.resetsAt || snapshot.status !== "ok") return [];
      return [{ providerID: snapshot.provider, accountID: snapshot.accountScope, capturedAt: snapshot.updatedAt,
        resetsAt: window.resetsAt, windowDurationSeconds: window.windowSeconds, remainingPercent: window.remainingPercent,
        coverage: "complete" as const }];
    });
    if (!additions.length) return;
    const existing = current.cockpitQuotaObservations ?? [];
    const next = [...existing];
    for (const observation of additions) {
      if (!next.some(item => item.providerID === observation.providerID && item.accountID === observation.accountID && item.capturedAt === observation.capturedAt)) next.push(observation);
    }
    if (next.length !== existing.length) {
      next.sort((a, b) => Date.parse(a.capturedAt) - Date.parse(b.capturedAt));
      try { await commitRuntime({ ...current, cockpitQuotaObservations: next.slice(-8192) }); }
      catch { if (alive.current) setError(zh ? "额度历史尚未保存，请稍后重试。" : "Quota history has not been saved; retry shortly."); }
    }
  }, [commitRuntime, zh]);

  const refresh = useCallback(async (force = false) => {
    if (refreshBusy.current) return;
    refreshBusy.current = true;
    if (alive.current) setRefreshing(true);
    const results = await Promise.allSettled([fetchSnapshots(force), fetchCodexResetForecast()]);
    if (alive.current) {
      if (results[0].status === "fulfilled") await publishSnapshots(results[0].value);
      else {
        setSnapshots(previous => previous.map(value => ({ ...value, status: "stale" as const })));
        setError(zh ? "额度刷新失败，保留上次快照。" : "Quota refresh failed; the previous snapshot is retained.");
      }
      if (results[1].status === "fulfilled") setForecast(results[1].value);
      // A failed public request must not erase a cache or turn an estimate into a confirmed notice.
      setRefreshing(false);
    }
    refreshBusy.current = false;
  }, [publishSnapshots, zh]);

  const refreshRef = useRef(refresh);
  refreshRef.current = refresh;
  useEffect(() => {
    alive.current = true;
    let active = true;
    void Promise.allSettled([getPreferences(), getRuntimeState(), getAppDiagnostics(), getAutostartEnabled()]).then(async result => {
      if (!active) return;
      const [prefs, state, diagnostics, startup] = result;
      if (prefs.status === "fulfilled") {
        const normalized = normalizeWidgetPreferences(prefs.value);
        preferenceWritable.current = true;
        preferencesRef.current = normalized;
        setPreferences(normalized);
      }
      if (state.status === "fulfilled") {
        writable.current = true;
        runtimeRef.current = state.value;
        setRuntime(state.value);
      }
      if (diagnostics.status === "fulfilled") setDiagnostics(diagnostics.value);
      if (startup.status === "fulfilled") setAutostart(startup.value);
      if (prefs.status === "rejected" || state.status === "rejected") {
        setError("Saved settings or history could not be read. Writing is paused to preserve the existing files.");
      }
      setReady(true);
      await refreshRef.current(true);
    });
    const timer = window.setInterval(() => { setNow(new Date()); void refreshRef.current(); }, 60_000);
    const focus = () => { setNow(new Date()); void refreshRef.current(true); };
    window.addEventListener("focus", focus);
    return () => { active = false; alive.current = false; window.clearInterval(timer); window.removeEventListener("focus", focus); };
  }, []);

  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    void listenDesktopEvents({ onPreferences: value => {
      const next = normalizeWidgetPreferences(value);
      preferencesRef.current = next; setPreferences(next);
    }, onRefresh: () => void refreshRef.current(true), onBackgroundSnapshots: values => void publishSnapshots(values), onUpdate: () => undefined })
      .then(value => { if (active) unsubscribe = value; else value(); })
      .catch(() => { if (active) setError("Desktop event updates are unavailable. Periodic refresh remains active."); });
    return () => { active = false; unsubscribe?.(); };
  }, [publishSnapshots]);

  useEffect(() => {
    if (typeof window.matchMedia !== "function") return;
    const query = window.matchMedia("(prefers-color-scheme: dark)");
    const change = () => setSystemDark(query.matches);
    query.addEventListener?.("change", change);
    return () => query.removeEventListener?.("change", change);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.appearance = resolveAppearanceMode(preferences.appearanceMode, systemDark);
    document.documentElement.dataset.fontFamily = preferences.fontFamily;
    document.documentElement.style.setProperty("--ui-font-scale", String(preferences.fontScale));
  }, [preferences.appearanceMode, preferences.fontFamily, preferences.fontScale, systemDark]);

  const observations = runtime.cockpitQuotaObservations ?? [];
  const ownFeedback = useMemo(() => runtime.comfortFeedback.filter(value => value.accountScope === scope && scope !== null), [runtime.comfortFeedback, scope]);
  const curve = useMemo(() => personalizeComfortCurve(ownFeedback), [ownFeedback]);
  const resetSignal = useMemo(() => cockpitResetSignal(forecast), [forecast]);
  const plan = useMemo(() => buildCockpitDailyPlan({ providerID: "codex", accountID: scope ?? "unavailable", now,
    snapshots: scope ? observations : [], comfortRecords: ownFeedback.filter(value => value.timeZoneIdentifier).map(value => ({ providerID: "codex", accountID: scope!, localDateKey: value.localDate, timeZoneIdentifier: value.timeZoneIdentifier!, recordedAt: value.updatedAt ?? value.observedAt, usedPercent: value.observedUsedPercent, feeling: value.comfort === "idle" ? "light" as const : value.comfort, coverage: value.usageCoverage })),
    personalCapPercent: preferences.dailyBudgetLocalDate === today && preferences.dailyBudgetAccountScope === scope ? preferences.dailyBudgetPercent : null,
    resetSignal,
  }), [scope, observations, now, ownFeedback, preferences.dailyBudgetLocalDate, preferences.dailyBudgetAccountScope, preferences.dailyBudgetPercent, today, resetSignal]);

  const dailyUsage: CodexDailyUsage[] = useMemo(() => {
    if (!scope) return [];
    const dates = [...new Set(observations.filter(value => value.providerID === "codex" && value.accountID === scope).map(value => localCalendarDay(new Date(value.capturedAt)).localDateKey))].sort();
    return dates.map(date => {
      const matching = observations.filter(value => value.providerID === "codex" && value.accountID === scope && localCalendarDay(new Date(value.capturedAt)).localDateKey === date);
      const last = matching.at(-1)!;
      const end = new Date(last.capturedAt);
      const status = date === today ? plan : buildCockpitDailyPlan({ providerID: "codex", accountID: scope, now: end, snapshots: observations });
      return { localDate: date, observedUsedPercent: status.usedPercent ?? 0, sampleCount: matching.length,
        firstObservedAt: matching[0].capturedAt, lastObservedAt: last.capturedAt, coverage: status.coverage,
        source: "official-snapshot" as const };
    });
  }, [scope, observations, today, plan]);

  useEffect(() => {
    if (!ready || !isTauri()) return;
    let active = true;
    void import("@tauri-apps/api/core").then(({ invoke }) => {
      if (!active) return;
      return invoke("update_tray", { percent: plan.remainingDailyBudgetPercent, weeklyPercent: plan.remainingSuggestedPercent,
        isUpperBound: plan.coverage !== "complete", isStale: plan.isStale || codex?.status === "stale",
        mode: preferences.trayMode ?? "circle", english: preferences.trayEnglish === true });
    }).catch(() => { if (active) setError(zh ? "托盘显示更新失败。" : "The tray display could not be updated."); });
    return () => { active = false; };
  }, [ready, plan.remainingDailyBudgetPercent, plan.remainingSuggestedPercent, plan.coverage, plan.isStale, codex?.status, preferences.trayMode, preferences.trayEnglish, zh]);

  const savePreferences = (next: WidgetPreferences) => {
    if (!preferenceWritable.current) return;
    const previous = preferencesRef.current;
    const normalized = normalizeWidgetPreferences(next);
    const sequence = ++preferenceSequence.current;
    preferencesRef.current = normalized; setPreferences(normalized);
    void updatePreferences(normalized).then(() => {
      if (sequence === preferenceSequence.current) applyPreviewDisplayMode(normalized.displayMode ?? "tray");
    }).catch(() => {
      if (sequence !== preferenceSequence.current) return;
      preferencesRef.current = previous; setPreferences(previous);
      setError(zh ? "设置未保存，已恢复原值。" : "Settings were not saved; the previous value was restored.");
    });
  };
  const saveFeedback = async (date: string, comfort: ComfortCode) => {
    if (!scope || feedbackBusy.current || !writable.current) return;
    feedbackBusy.current = true; setSavingFeedback(true);
    const current = runtimeRef.current;
    const existing = current.comfortFeedback.find(value => value.localDate === date && value.accountScope === scope);
    const captured = dailyUsage.find(value => value.localDate === date);
    const record = existing ? { ...existing, comfort, updatedAt: new Date().toISOString() } : {
      ...createComfortFeedbackRecord({ localDate: date, isCatchUp: date !== today, observedUsedPercent: captured?.observedUsedPercent ?? null,
        usageCoverage: captured?.coverage ?? "unavailable", usageObservedAt: captured?.lastObservedAt ?? null,
        usageSource: captured ? "official-snapshot" : "unavailable" }, comfort), accountScope: scope, timeZoneIdentifier: localCalendarDay(now).timeZoneIdentifier,
    };
    const records = current.comfortFeedback.filter(value => !(value.localDate === date && value.accountScope === scope));
    try { await commitRuntime({ ...current, comfortFeedback: [...records, record] }); }
    catch { setError(zh ? "体验记录未写入磁盘，请重试。" : "The experience entry has not been saved; retry."); }
    finally { feedbackBusy.current = false; setSavingFeedback(false); }
  };
  const setLaunchAtLogin = async (enabled: boolean) => {
    try { setAutostart(await setAutostartEnabled(enabled)); }
    catch { setError(zh ? "无法修改登录启动选项。" : "Launch at login could not be changed."); }
  };

  const windowAction = (operation: () => Promise<void>) => {
    void operation().catch(() => setError(zh ? "窗口操作未完成，请从托盘重试。" : "Window action failed. Retry from the tray."));
  };
  return <>
    {surface === "compact" && <FloatingSummary preferences={preferences} snapshots={snapshots} plan={plan}
    startupReady={ready} refreshing={refreshing} error={error}
    onOpen={page => windowAction(() => openFullPanel(page))} onHide={() => windowAction(hidePanel)}
    onDrag={() => windowAction(beginFloatingDrag)} onRefresh={() => { setError(null); void refresh(true); }} />}

    <div hidden={surface !== "panel"} style={{ width: "100%", height: "100%" }}>
    <TrayPanel preferences={preferences} onPreferences={savePreferences} snapshots={snapshots} plan={plan} pageRequest={pageRequest}
    history={observations.filter(value => value.accountID === scope && value.providerID === "codex")} forecast={forecast} now={now}
    usage={usage} usageError={usageError} onUsageRefresh={refreshUsage} diagnostics={diagnostics} startupReady={ready}
    settingsWritable={preferenceWritable.current} error={error} onDismissError={() => setError(null)} refreshing={refreshing}
    onRefresh={() => { setError(null); void refresh(true); void refreshUsage().catch(() => undefined); }}
    onHide={() => windowAction(preferences.displayMode === "floating" ? compactPanel : hidePanel)}
    onFeedback={(date, value) => void saveFeedback(date, value)} feedback={ownFeedback} dailyUsage={dailyUsage} curve={curve}
    savingFeedback={savingFeedback} canRecordFeedback={Boolean(scope)} autostart={autostart} onAutostart={enabled => void setLaunchAtLogin(enabled)}
    onPersonalCap={value => savePreferences({ ...preferencesRef.current, dailyBudgetPercent: value ?? 0, dailyBudgetLocalDate: value === null ? null : today, dailyBudgetAccountScope: value === null ? null : scope })} />
    </div>
  </>;
}
