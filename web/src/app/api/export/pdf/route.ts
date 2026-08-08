import { NextRequest, NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { listDrives } from "@/lib/drives";
import { buildPDF } from "@/lib/report";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const denied = await requireAuth(req);
  if (denied) return denied;

  const params = req.nextUrl.searchParams;
  const year = Number(params.get("year"));
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    return NextResponse.json({ error: "year is required" }, { status: 400 });
  }
  const quarterRaw = params.get("quarter");
  const quarter = quarterRaw ? Number(quarterRaw) : undefined;
  if (quarter !== undefined && ![1, 2, 3, 4].includes(quarter)) {
    return NextResponse.json({ error: "quarter must be 1-4" }, { status: 400 });
  }
  const categoryRaw = params.get("category");
  const category =
    categoryRaw === "business" || categoryRaw === "personal"
      ? categoryRaw
      : undefined;

  const drives = await listDrives({ year, quarter, category });
  const pdf = buildPDF(drives, { year, quarter, category });
  const suffix = quarter ? `${year}-Q${quarter}` : `${year}`;
  return new NextResponse(Buffer.from(pdf), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="miles-report-${suffix}.pdf"`,
    },
  });
}
