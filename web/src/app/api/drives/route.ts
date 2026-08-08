import { NextRequest, NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";
import {
  CATEGORIES,
  type Category,
  driveSchema,
  filterConditions,
  rowToDTO,
  upsertDrive,
} from "@/lib/drives";

export async function GET(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;

  const params = req.nextUrl.searchParams;
  const year = params.get("year") ? Number(params.get("year")) : undefined;
  const month = params.get("month") ? Number(params.get("month")) : undefined;
  const quarter = params.get("quarter")
    ? Number(params.get("quarter"))
    : undefined;
  const rawCategory = params.get("category") ?? undefined;
  const category =
    rawCategory && (CATEGORIES as readonly string[]).includes(rawCategory)
      ? (rawCategory as Category)
      : undefined;
  const limit = Math.min(Number(params.get("limit") ?? 500), 2000);
  const offset = Math.max(Number(params.get("offset") ?? 0), 0);

  const where = filterConditions({ year, month, quarter, category });
  const [rows, totals] = await Promise.all([
    sql`
      select * from drives where ${where}
      order by started_at desc
      limit ${limit} offset ${offset}
    `,
    sql`
      select
        count(*)::int as count,
        coalesce(sum(distance_miles), 0) as miles,
        coalesce(sum(distance_miles) filter (where category = 'business'), 0) as business_miles,
        coalesce(sum(distance_miles * rate_cents_per_mile / 100.0)
          filter (where category = 'business'), 0) as deduction
      from drives where ${where}
    `,
  ]);

  return NextResponse.json({
    drives: rows.map(rowToDTO),
    totals: {
      count: totals[0].count,
      miles: Number(totals[0].miles),
      businessMiles: Number(totals[0].business_miles),
      deduction: Number(totals[0].deduction),
    },
  });
}

export async function POST(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;

  const parsed = driveSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid drive", details: parsed.error.flatten() },
      { status: 400 }
    );
  }
  await upsertDrive(parsed.data);
  const [row] = await sql`select * from drives where id = ${parsed.data.id}`;
  return NextResponse.json({ drive: rowToDTO(row) }, { status: 201 });
}
