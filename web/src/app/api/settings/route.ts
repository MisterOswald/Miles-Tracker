import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";

const putSchema = z.object({
  key: z.string().min(1).max(100),
  value: z.unknown(),
});

export async function GET(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const rows = await sql`select key, value from settings`;
  const settings: Record<string, unknown> = {};
  for (const r of rows) settings[r.key] = r.value;
  return NextResponse.json({ settings });
}

export async function PUT(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const parsed = putSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid setting" }, { status: 400 });
  }
  await sql`
    insert into settings (key, value, updated_at)
    values (${parsed.data.key}, ${JSON.stringify(parsed.data.value)}::jsonb, now())
    on conflict (key) do update set
      value = excluded.value, updated_at = now()
  `;
  return NextResponse.json({ ok: true });
}
