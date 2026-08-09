import { notFound } from "next/navigation";
import { z } from "zod";
import { sql } from "@/lib/db";
import { rowToDTO } from "@/lib/drives";
import { decodePolyline } from "@/lib/polyline";
import DriveDetailClient from "@/components/DriveDetailClient";

export const dynamic = "force-dynamic";

export default async function DriveDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!z.string().uuid().safeParse(id).success) notFound();

  const [row] = await sql`
    select * from drives where id = ${id} and deleted_at is null
  `;
  if (!row) notFound();
  const drive = rowToDTO(row);

  let route = decodePolyline(drive.polyline);
  if (
    route.length === 0 &&
    drive.startLat != null &&
    drive.startLng != null &&
    drive.endLat != null &&
    drive.endLng != null
  ) {
    route = [
      [drive.startLat, drive.startLng],
      [drive.endLat, drive.endLng],
    ];
  }

  return <DriveDetailClient drive={drive} route={route} />;
}
