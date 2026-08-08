import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";

const putSchema = z.object({
  year: z.number().int().min(2000).max(2100),
  centsPerMile: z.number().min(0).max(10000),
  // Also update the snapshotted rate on existing drives for that year.
  applyToExistingDrives: z.boolean().default(false),
});

export async function GET(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const rows = await sql`select year, cents_per_mile from rates order by year desc`;
  return NextResponse.json({
    rates: rows.map((r) => ({
      year: r.year,
      centsPerMile: Number(r.cents_per_mile),
    })),
  });
}

export async function PUT(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const parsed = putSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid rate", details: parsed.error.flatten() },
      { status: 400 }
    );
  }
  const { year, centsPerMile, applyToExistingDrives } = parsed.data;
  await sql`
    insert into rates (year, cents_per_mile)
    values (${year}, ${centsPerMile})
    on conflict (year) do update set cents_per_mile = excluded.cents_per_mile
  `;
  if (applyToExistingDrives) {
    await sql`
      update drives
      set rate_cents_per_mile = ${centsPerMile}, updated_at = now()
      where extract(year from started_at) = ${year} and deleted_at is null
    `;
  }
  return NextResponse.json({ ok: true });
}
