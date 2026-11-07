import { isTauri } from "./bridge";

export interface CloudMember {
  deviceId: string;
  displayName: string;
  role: string;
  updatedAt: number | null;
  syncInfo?: { protocolVersion: number; appVersion: string; settingsRevision: number } | null;
  costCoverage?: { knownModels: number; totalModels: number };
}

export interface CloudSyncStatus {
  config: {
    endpoint: string;
    shareTaskDetails: boolean;
    deviceId: string;
    spaceId: string;
    spaceName: string;
    role: string;
    enabled: boolean;
    intervalSeconds: number;
  } | null;
  members: CloudMember[];
  lastPulledAt?: string | null;
  sharedRevision?: number;
  pricingReady?: boolean;
}

/** Read the native cache of the connection and device roster. */
export async function getCloudSyncStatus(): Promise<CloudSyncStatus> {
  if (!isTauri()) return { config: null, members: [] };
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke("get_cloud_sync_status");
}
