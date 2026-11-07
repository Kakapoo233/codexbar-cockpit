import type { CloudMember } from "./cloudSyncStatus";
import { groupColors } from "./dailyPersonCosts";
import { aggregateGlobalUsage, type TokeiUsage } from "./tokeiUsage";
import { newestDevices } from "./usageCalendar";

export type MemberUsagePeriod = "today" | "7d";

export function buildMemberUsage(data: TokeiUsage, members: CloudMember[], period: MemberUsagePeriod, now: Date, overrides: Record<string, string> = {}) {
  const snapshots = new Map(newestDevices(data.devices).map(device => [device.id, device]));
  const roster = new Map(members.map(member => [member.deviceId, member]));
  const colors = groupColors(data.groups.map(group => group.id));
  const devices = [...snapshots.values()].map(device => device.timeZonePending ? { ...device, daily: {}, ranges: {} } : device);
  for (const id of roster.keys()) {
    // A registered device without a snapshot still belongs in the roster and in coverage checks.
    if (!snapshots.has(id)) devices.push({ id, updatedAt: null, stale: false, daily: {}, ranges: {} });
  }
  const summary = aggregateGlobalUsage({ ...data, devices }, period, now);
  const people = summary.users.map(user => {
    const ids = [...user.devices.map(device => device.id), ...user.missingDeviceIds];
    const deviceRows = ids.map(id => {
      const snapshot = snapshots.get(id);
      return {
        id, name: roster.get(id)?.displayName || id, updatedAt: snapshot?.updatedAt,
        missingSnapshot: !snapshot, dayPending: Boolean(snapshot?.timeZonePending),
        hasRecord: Boolean(snapshot) && !user.unavailablePeriodDeviceIds.includes(id),
        stale: Boolean(snapshot?.stale), partial: Boolean(snapshot?.collectionPartial),
      };
    });
    const partial = deviceRows.some(device => !device.hasRecord || device.stale || device.partial);
    const override = overrides[user.id];
    const color = colors.has(user.id) && /^#[0-9a-f]{6}$/i.test(override) ? override : colors.get(user.id) ?? "#929baa";
    return {
      id: user.id, name: user.name, color, unassigned: !colors.has(user.id), devices: deviceRows,
      tokens: user.hasData ? user.totalTokens : null,
      tokenShare: user.hasData && summary.totalTokens > 0 ? user.totalTokens / summary.totalTokens : null,
      cost: user.knownCostUsd, partial, costPartial: partial || user.costIncomplete,
    };
  });
  const partial = data.status !== "ready" || people.some(person => person.partial);
  return {
    people, partial, tokens: summary.hasData ? summary.totalTokens : null, cost: summary.knownCostUsd,
    costPartial: partial || people.some(person => person.devices.length > 0 && person.costPartial),
  };
}
