// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { getCloudSyncStatus, type CloudSyncStatus } from "../lib/cloudSyncStatus";
import type { DailyModelUsage, TokeiDevice, TokeiUsage } from "../lib/tokeiUsage";
import { TeamUsagePanel } from "./TeamUsagePanel";

vi.mock("../lib/cloudSyncStatus", () => ({ getCloudSyncStatus: vi.fn() }));
const readCloudStatus = vi.mocked(getCloudSyncStatus);
beforeEach(() => readCloudStatus.mockReset().mockResolvedValue({ config: null, members: [] }));
afterEach(cleanup);

const now = new Date("2026-11-01T16:05:00Z");
const today = "2026-11-02";
const earlier = "2026-11-01";
function record(tokens: number, cost: number | null): DailyModelUsage {
  return { inputTokens: tokens, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0, totalTokens: tokens, estimatedCostUsd: cost, models: [] };
}
function device(id: string, daily: TokeiDevice["daily"]): TokeiDevice {
  return { id, daily, ranges: {}, stale: false, updatedAt: now.toISOString() };
}
function usage(groups: TokeiUsage["groups"], devices: TokeiDevice[]): TokeiUsage {
  return { groups, devices, fetchedAt: now.toISOString(), status: "ready", defaultGroupId: null, warnings: [], projectBreakdownAvailable: false };
}
const connected: CloudSyncStatus["config"] = {
  endpoint: "https://example.workers.dev", shareTaskDetails: false, deviceId: "first", spaceId: "fixture", spaceName: "Fixture team", role: "member", enabled: true, intervalSeconds: 300,
};
const props = { loadingError: false, now, zh: false, refreshVersion: 0, onOpenSettings: vi.fn() };

it("uses recorded tokens, deduplicates devices and separates measured zero from missing data", async () => {
  readCloudStatus.mockResolvedValue({ config: connected, members: [{ deviceId: "new-pc", displayName: "New laptop", role: "member", updatedAt: null }] });
  const data = usage([
    { id: "first", name: "First member", deviceIds: ["first", "missing"] },
    { id: "second", name: "Second member", deviceIds: ["first", "zero"] },
    { id: "third", name: "Third member", deviceIds: ["waiting"] },
  ], [
    { ...device("first", { [today]: record(900, 9) }), updatedAt: "2026-11-01T16:02:00Z" },
    device("first", { [today]: record(300, 3) }),
    device("zero", { [today]: record(0, 0) }),
    device("unassigned", { [today]: record(100, null) }),
  ]);
  render(<TeamUsagePanel {...props} usage={data} />);
  const first = within(screen.getByRole("article", { name: "First member" }));
  expect(first.getByText("300")).toBeInTheDocument();
  expect(first.getByText("75%")).toBeInTheDocument();
  expect(first.getByText("$3.00")).toBeInTheDocument();
  expect(first.getByText("Known estimated cost")).toBeInTheDocument();
  const second = within(screen.getByRole("article", { name: "Second member" }));
  expect(second.getByText("0")).toBeInTheDocument();
  expect(second.getByText("0%")).toBeInTheDocument();
  const third = within(screen.getByRole("article", { name: "Third member" }));
  expect(third.getAllByText("—")).toHaveLength(3);
  expect(third.queryByText("0%")).not.toBeInTheDocument();
  const unassigned = within(screen.getByRole("article", { name: "Unassigned devices" }));
  expect(unassigned.getByText("25%")).toBeInTheDocument();
  expect(await unassigned.findByText("New laptop")).toBeInTheDocument();
  expect(unassigned.getByText("No usage snapshot")).toBeInTheDocument();
  expect(screen.getByText("400")).toBeInTheDocument();
  expect(screen.getByText(/Usage coverage is incomplete/)).toBeInTheDocument();
});

it("uses Shanghai dates, excludes pending legacy buckets and presents paused cache status", async () => {
  readCloudStatus.mockResolvedValue({ config: { ...connected, enabled: false }, members: [], lastPulledAt: now.toISOString() });
  const data = usage([{ id: "first", name: "First member", deviceIds: ["first", "legacy"] }], [
    { ...device("first", { [earlier]: record(200, 2) }), stale: true },
    { ...device("legacy", { [today]: record(500, 5) }), timeZonePending: true },
  ]);
  const { rerender } = render(<TeamUsagePanel {...props} usage={data} />);
  expect(await screen.findByText(/Cloud sync is paused/)).toBeInTheDocument();
  expect(screen.getByText(/Last cloud download/)).toBeInTheDocument();
  expect(screen.getByText(`${today} · Shanghai time`)).toBeInTheDocument();
  expect(screen.getByText("No usage records for this period.")).toBeInTheDocument();
  expect(screen.getByText(/Reporting-day migration pending/)).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Last 7 days" }));
  expect(screen.getByText(`2026-10-27 – ${today} · Shanghai time`)).toBeInTheDocument();
  const member = within(screen.getByRole("article", { name: "First member" }));
  expect(member.getByText("200")).toBeInTheDocument();
  expect(member.getByText(/Earlier snapshot/)).toBeInTheDocument();
  expect(screen.queryByText("500")).not.toBeInTheDocument();
  rerender(<TeamUsagePanel {...props} usage={data} refreshVersion={1} />);
  await waitFor(() => expect(readCloudStatus).toHaveBeenCalledTimes(2));
});
