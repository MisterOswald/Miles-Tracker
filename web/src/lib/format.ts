import type { DriveDTO } from "./drives";

export function deductionDollars(drive: {
  distanceMiles: number;
  rateCentsPerMile: number;
  category: string;
}): number {
  if (drive.category !== "business") return 0;
  return (drive.distanceMiles * drive.rateCentsPerMile) / 100;
}

export function formatMiles(miles: number): string {
  return `${miles.toFixed(1)} mi`;
}

export function formatMoney(dollars: number): string {
  return dollars.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });
}

export function formatDuration(drive: DriveDTO): string {
  const ms =
    new Date(drive.endedAt).getTime() - new Date(drive.startedAt).getTime();
  const minutes = Math.max(1, Math.round(ms / 60000));
  if (minutes < 60) return `${minutes} min`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}
