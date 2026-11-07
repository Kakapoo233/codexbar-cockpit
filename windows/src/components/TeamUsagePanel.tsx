import { useEffect, useMemo, useState } from "react";
import { getCloudSyncStatus, type CloudSyncStatus } from "../lib/cloudSyncStatus";
import { buildMemberUsage, type MemberUsagePeriod } from "../lib/memberUsage";
import { formatCost, formatTokens, periodStart, type TokeiUsage } from "../lib/tokeiUsage";
import { localDateKey, USAGE_TIME_ZONE } from "../lib/usageDay";

interface Props {
  usage: TokeiUsage | null;
  loadingError: boolean;
  now: Date;
  zh: boolean;
  colors?: Record<string, string>;
  refreshVersion: number;
  onOpenSettings: () => void;
}

export function TeamUsagePanel({ usage, loadingError, now, zh, colors, refreshVersion, onOpenSettings }: Props) {
  const [period, setPeriod] = useState<MemberUsagePeriod>("today");
  const [cloud, setCloud] = useState<CloudSyncStatus | null>(null);
  const [rosterError, setRosterError] = useState(false);
  useEffect(() => {
    let active = true;
    void getCloudSyncStatus().then(status => {
      if (active) { setCloud(status); setRosterError(false); }
    }, () => { if (active) setRosterError(true); });
    return () => { active = false; };
  }, [usage?.fetchedAt, refreshVersion]);
  const summary = useMemo(() => usage && buildMemberUsage(usage, cloud?.config ? cloud.members : [], period, now, colors), [usage, cloud, period, now, colors]);
  const locale = zh ? "zh-CN" : "en-US";
  const formatShare = new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 1 });
  const formatUpdated = new Intl.DateTimeFormat(locale, { timeZone: USAGE_TIME_ZONE, month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
  const start = periodStart(period, now);
  const today = localDateKey(now);
  const lastPulled = Date.parse(cloud?.lastPulledAt ?? "");

  return <>
    <section className="tray-card team-usage" aria-labelledby="team-usage-title">
      <header className="team-usage-heading">
        <h2 id="team-usage-title">{zh ? "组员用量分布" : "Member usage distribution"}</h2>
        <button type="button" onClick={onOpenSettings}>{zh ? "打开组员设置" : "Open member settings"}</button>
      </header>
      <div className="team-usage-period">
        <div role="group" aria-label={zh ? "组员用量时段" : "Member usage period"}>
          <button type="button" aria-pressed={period === "today"} onClick={() => setPeriod("today")}>{zh ? "今日" : "Today"}</button>
          <button type="button" aria-pressed={period === "7d"} onClick={() => setPeriod("7d")}>{zh ? "近 7 天" : "Last 7 days"}</button>
        </div>
        <small>{start === today ? today : `${start} – ${today}`} · {zh ? "上海时间" : "Shanghai time"}</small>
      </div>
      {cloud?.config?.enabled === false && <p className="usage-note">{zh ? "云同步已暂停，其他设备用量来自缓存。" : "Cloud sync is paused. Other devices' usage comes from cached data."}</p>}
      {cloud?.config && Number.isFinite(lastPulled) && <p className="usage-note">{zh ? "最近接收云端数据" : "Last cloud download"} · {formatUpdated.format(lastPulled)}</p>}
      {rosterError && <p className="usage-note" role="status">{zh ? "暂时无法更新云端设备列表。" : "The cloud device list could not be refreshed."}</p>}
      {!summary ? <p className={loadingError ? "usage-error" : "usage-note"} role="status">{loadingError
        ? (zh ? "暂时无法读取组员用量，请刷新重试。" : "Member usage is unavailable. Refresh to retry.")
        : (zh ? "正在读取组员用量…" : "Loading member usage…")}</p> : <>
        <dl className="team-usage-metrics">
          <div><dt>{zh ? "已记录 Token 总量" : "Total recorded tokens"}</dt><dd>{summary.tokens === null ? "—" : formatTokens(summary.tokens, zh)}</dd></div>
          <div><dt>{summary.cost !== null && (summary.costPartial || loadingError || rosterError)
            ? (zh ? "已知估算费用（USD）" : "Known estimated cost (USD)") : (zh ? "估算费用（USD）" : "Estimated cost (USD)")}</dt>
          <dd>{summary.cost === null ? "—" : formatCost(summary.cost, zh)}</dd></div>
        </dl>
        {summary.tokens === null ? <p className="usage-note">{zh ? "所选时段暂无用量记录。" : "No usage records for this period."}</p>
          : <p className="usage-note">{zh ? "份额按本机与已接收设备的 Codex Token 记录计算，含未归属设备。" : "Shares use Codex tokens recorded on this computer and received from devices, including unassigned devices."}</p>}
        {loadingError && <p className="usage-note" role="status">{zh ? "刷新失败，当前显示上次读取的用量。" : "Refresh failed. Showing the last available usage."}</p>}
        {summary.tokens !== null && summary.partial && <p className="usage-note">{zh ? "用量覆盖不完整，以下仅显示已有记录。" : "Usage coverage is incomplete. Only available records are included."}</p>}
      </>}
    </section>
    {summary && <section className="tray-card team-member-list" aria-labelledby="team-member-list-title">
      <h2 id="team-member-list-title">{zh ? "组员与设备" : "Members & devices"}</h2>
      {summary.people.length === 0 && <p className="usage-note">{zh ? "暂无组员或设备。" : "No members or devices yet."}</p>}
      {summary.people.map(person => {
        const name = person.unassigned ? (zh ? "未归属设备" : "Unassigned devices") : person.name;
        const share = person.tokenShare;
        const title = `team-member-${person.id}`;
        return <article key={person.id} className="team-member-usage" aria-labelledby={title}>
          <h3 id={title}><i aria-hidden="true" style={{ background: person.color }} />{name}</h3>
          <dl className="team-usage-metrics">
            <div><dt>{zh ? "已记录 Token" : "Recorded tokens"}</dt><dd>{person.tokens === null ? "—" : formatTokens(person.tokens, zh)}</dd></div>
            <div><dt>{zh ? "Token 份额" : "Token share"}</dt><dd>{share === null ? "—" : formatShare.format(share)}</dd></div>
            <div><dt>{person.cost !== null && person.costPartial
              ? (zh ? "已知估算费用" : "Known estimated cost") : (zh ? "估算费用" : "Estimated cost")}</dt>
            <dd>{person.cost === null ? "—" : formatCost(person.cost, zh)}</dd></div>
          </dl>
          {share !== null && <div className="tray-meter-track" aria-hidden="true"><i style={{ width: `${share * 100}%`, background: person.color }} /></div>}
          {person.partial && <p className="usage-note">{person.tokens === null ? (zh ? "所选时段暂无记录" : "No records for this period") : (zh ? "记录不完整" : "Incomplete records")}</p>}
          {person.devices.length ? <details className="team-device-list">
            <summary>{zh ? `${person.devices.length} 台设备` : `${person.devices.length} ${person.devices.length === 1 ? "device" : "devices"}`}</summary>
            <ul>{person.devices.map(device => {
              const updated = Date.parse(device.updatedAt ?? "");
              const status = device.missingSnapshot ? (zh ? "暂无用量快照" : "No usage snapshot")
                : device.dayPending ? (zh ? "等待日界迁移" : "Reporting-day migration pending")
                : !device.hasRecord ? (zh ? "所选时段暂无记录" : "No record for this period")
                : device.stale ? (zh ? "较早的快照" : "Earlier snapshot")
                : device.partial ? (zh ? "快照不完整" : "Incomplete snapshot")
                : (zh ? "有用量记录" : "Usage recorded");
              return <li key={device.id}>
                <strong>{device.name}</strong>
                {device.name !== device.id && <small>{device.id}</small>}
                <small>{status}{Number.isFinite(updated) && ` · ${formatUpdated.format(updated)}`}</small>
              </li>;
            })}</ul>
          </details> : <small className="team-no-devices">{zh ? "尚未分配设备" : "No devices assigned"}</small>}
        </article>;
      })}
    </section>}
  </>;
}
