import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";
import { drivePatchSchema, rowToDTO } from "@/lib/drives";

const idSchema = z.string().uuid();

type Params = { params: Promise<{ id: string }> };

export async function GET(req: NextRequest, { params }: Params) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const { id } = await params;
  if (!idSchema.safeParse(id).success) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }
  const [row] = await sql`
    select * from drives where id = ${id} and deleted_at is null
  `;
  if (!row) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ drive: rowToDTO(row) });
}

export async function PATCH(req: NextRequest, { params }: Params) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const { id } = await params;
  if (!idSchema.safeParse(id).success) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }
  const parsed = drivePatchSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid patch", details: parsed.error.flatten() },
      { status: 400 }
    );
  }
  const p = parsed.data;
  const [row] = await sql`
    update drives set
      started_at = coalesce(${p.startedAt ?? null}, started_at),
      ended_at = coalesce(${p.endedAt ?? null}, ended_at),
      distance_miles = coalesce(${p.distanceMiles ?? null}, distance_miles),
      start_address = coalesce(${p.startAddress ?? null}, start_address),
      end_address = coalesce(${p.endAddress ?? null}, end_address),
      category = coalesce(${p.category ?? null}, category),
      purpose_note = coalesce(${p.purposeNote ?? null}, purpose_note),
      rate_cents_per_mile = coalesce(${p.rateCentsPerMile ?? null}, rate_cents_per_mile),
      updated_at = now()
    where id = ${id} and deleted_at is null
    returning *
  `;
  if (!row) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ drive: rowToDTO(row) });
}

export async function DELETE(req: NextRequest, { params }: Params) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const { id } = await params;
  if (!idSchema.safeParse(id).success) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }
  const [row] = await sql`
    update drives set deleted_at = now(), updated_at = now()
    where id = ${id} and deleted_at is null
    returning id
  `;
  if (!row) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
