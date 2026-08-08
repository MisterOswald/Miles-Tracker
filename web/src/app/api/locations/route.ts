import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireAuth } from "@/lib/auth";
import { sql } from "@/lib/db";

const locationSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1).max(100),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  radiusMeters: z.number().min(25).max(5000).default(150),
  category: z.enum(["business", "personal"]).nullish(),
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToLocation(r: any) {
  return {
    id: r.id,
    name: r.name,
    lat: Number(r.lat),
    lng: Number(r.lng),
    radiusMeters: Number(r.radius_meters),
    category: r.category,
  };
}

export async function GET(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const rows = await sql`select * from locations order by name asc`;
  return NextResponse.json({ locations: rows.map(rowToLocation) });
}

export async function POST(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;
  const parsed = locationSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid location", details: parsed.error.flatten() },
      { status: 400 }
    );
  }
  const l = parsed.data;
  const [row] = await sql`
    insert into locations (id, name, lat, lng, radius_meters, category, updated_at)
    values (${l.id}, ${l.name}, ${l.lat}, ${l.lng}, ${l.radiusMeters},
            ${l.category ?? null}, now())
    on conflict (id) do update set
      name = excluded.name,
      lat = excluded.lat,
      lng = excluded.lng,
      radius_meters = excluded.radius_meters,
      category = excluded.category,
      updated_at = now()
    returning *
  `;
  return NextResponse.json({ location: rowToLocation(row) }, { status: 201 });
}
