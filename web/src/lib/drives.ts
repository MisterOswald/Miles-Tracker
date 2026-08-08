import { z } from "zod";
import { sql } from "./db";

export const CATEGORIES = ["unclassified", "business", "personal"] as const;
export type Category = (typeof CATEGORIES)[number];

export interface DriveDTO {
  id: string;
  startedAt: string;
  endedAt: string;
  distanceMiles: number;
  startLat: number | null;
  startLng: number | null;
  endLat: number | null;
  endLng: number | null;
  startAddress: string;
  endAddress: string;
  category: Category;
  purposeNote: string;
  rateCentsPerMile: number;
  polyline: string;
  source: "auto" | "manual" | "merged";
  updatedAt: string;
  deletedAt: string | null;
}

export const driveSchema = z.object({
  id: z.string().uuid(),
  startedAt: z.string().datetime({ offset: true }),
  endedAt: z.string().datetime({ offset: true }),
  distanceMiles: z.number().min(0).max(20000),
  startLat: z.number().min(-90).max(90).nullish(),
  startLng: z.number().min(-180).max(180).nullish(),
  endLat: z.number().min(-90).max(90).nullish(),
  endLng: z.number().min(-180).max(180).nullish(),
  startAddress: z.string().max(500).default(""),
  endAddress: z.string().max(500).default(""),
  category: z.enum(CATEGORIES).default("unclassified"),
  purposeNote: z.string().max(2000).default(""),
  rateCentsPerMile: z.number().min(0).max(10000).default(0),
  polyline: z.string().max(500_000).default(""),
  source: z.enum(["auto", "manual", "merged"]).default("auto"),
  updatedAt: z.string().datetime({ offset: true }),
  deletedAt: z.string().datetime({ offset: true }).nullish(),
});

export const drivePatchSchema = driveSchema
  .pick({
    startedAt: true,
    endedAt: true,
    distanceMiles: true,
    startAddress: true,
    endAddress: true,
    category: true,
    purposeNote: true,
    rateCentsPerMile: true,
  })
  .partial();

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function rowToDTO(row: any): DriveDTO {
  return {
    id: row.id,
    startedAt: new Date(row.started_at).toISOString(),
    endedAt: new Date(row.ended_at).toISOString(),
    distanceMiles: Number(row.distance_miles),
    startLat: row.start_lat === null ? null : Number(row.start_lat),
    startLng: row.start_lng === null ? null : Number(row.start_lng),
    endLat: row.end_lat === null ? null : Number(row.end_lat),
    endLng: row.end_lng === null ? null : Number(row.end_lng),
    startAddress: row.start_address,
    endAddress: row.end_address,
    category: row.category,
    purposeNote: row.purpose_note,
    rateCentsPerMile: Number(row.rate_cents_per_mile),
    polyline: row.polyline,
    source: row.source,
    updatedAt: new Date(row.updated_at).toISOString(),
    deletedAt: row.deleted_at ? new Date(row.deleted_at).toISOString() : null,
  };
}

/**
 * Last-write-wins upsert used by both the sync endpoint and drive creation.
 * An incoming drive only overwrites an existing row when its updatedAt is
 * newer than what the server has.
 */
export async function upsertDrive(drive: z.infer<typeof driveSchema>) {
  await sql`
    insert into drives (
      id, started_at, ended_at, distance_miles,
      start_lat, start_lng, end_lat, end_lng,
      start_address, end_address, category, purpose_note,
      rate_cents_per_mile, polyline, source, updated_at, deleted_at
    ) values (
      ${drive.id}, ${drive.startedAt}, ${drive.endedAt}, ${drive.distanceMiles},
      ${drive.startLat ?? null}, ${drive.startLng ?? null},
      ${drive.endLat ?? null}, ${drive.endLng ?? null},
      ${drive.startAddress}, ${drive.endAddress}, ${drive.category},
      ${drive.purposeNote}, ${drive.rateCentsPerMile}, ${drive.polyline},
      ${drive.source}, ${drive.updatedAt}, ${drive.deletedAt ?? null}
    )
    on conflict (id) do update set
      started_at = excluded.started_at,
      ended_at = excluded.ended_at,
      distance_miles = excluded.distance_miles,
      start_lat = excluded.start_lat,
      start_lng = excluded.start_lng,
      end_lat = excluded.end_lat,
      end_lng = excluded.end_lng,
      start_address = excluded.start_address,
      end_address = excluded.end_address,
      category = excluded.category,
      purpose_note = excluded.purpose_note,
      rate_cents_per_mile = excluded.rate_cents_per_mile,
      polyline = excluded.polyline,
      source = excluded.source,
      updated_at = excluded.updated_at,
      deleted_at = excluded.deleted_at
    where drives.updated_at < excluded.updated_at
  `;
}

export interface DriveFilters {
  year?: number;
  month?: number;
  quarter?: number;
  category?: Category;
}

export function filterConditions(f: DriveFilters) {
  const conds = [sql`deleted_at is null`];
  if (f.year) {
    conds.push(sql`extract(year from started_at) = ${f.year}`);
  }
  if (f.month) {
    conds.push(sql`extract(month from started_at) = ${f.month}`);
  }
  if (f.quarter) {
    conds.push(sql`extract(quarter from started_at) = ${f.quarter}`);
  }
  if (f.category) {
    conds.push(sql`category = ${f.category}`);
  }
  return conds.reduce((acc, c) => sql`${acc} and ${c}`);
}

export async function listDrives(f: DriveFilters): Promise<DriveDTO[]> {
  const rows = await sql`
    select * from drives
    where ${filterConditions(f)}
    order by started_at desc
  `;
  return rows.map(rowToDTO);
}
