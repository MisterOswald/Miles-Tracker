import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";
import { driveSchema, rowToDTO, upsertDrive } from "@/lib/drives";

const syncSchema = z.object({
  // ISO timestamp of the last successful sync; null on first sync.
  cursor: z.string().datetime({ offset: true }).nullish(),
  // Locally-changed drives to push. Last-write-wins by updatedAt.
  drives: z.array(driveSchema).max(2000).default([]),
});

/**
 * Bulk sync used by the iOS app.
 * 1. Upserts every pushed drive (a stale push never overwrites newer server
 *    state, so classification edits made on the web win over older device
 *    state).
 * 2. Returns every drive changed since the cursor — including soft-deleted
 *    ones so the device can remove them — plus a new cursor.
 */
export async function POST(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;

  const parsed = syncSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid sync payload", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [{ now: serverTime }] = await sql`select now() as now`;

  for (const drive of parsed.data.drives) {
    await upsertDrive(drive);
  }

  const cursor = parsed.data.cursor ?? null;
  const changed = cursor
    ? await sql`
        select * from drives
        where updated_at > ${cursor} and updated_at <= ${serverTime}
        order by updated_at asc
        limit 5000
      `
    : await sql`
        select * from drives
        where updated_at <= ${serverTime}
        order by updated_at asc
        limit 5000
      `;

  return NextResponse.json({
    serverTime: new Date(serverTime).toISOString(),
    drives: changed.map(rowToDTO),
  });
}
