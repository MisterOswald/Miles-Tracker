import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { sql } from "@/lib/db";
import { rowToDTO } from "@/lib/drives";
import { decodePolyline } from "@/lib/polyline";
import {
  deductionDollars,
  formatDate,
  formatDuration,
  formatMoney,
  formatTime,
} from "@/lib/format";
import MapView from "@/components/map/MapView";
import DriveEditor from "@/components/DriveEditor";

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

  return (
    <main>
      <p style={{ marginTop: 0 }}>
        <Link href="/drives">← All drives</Link>
      </p>
      <h1>
        {formatDate(drive.startedAt)}{" "}
        <span style={{ color: "var(--text-muted)", fontWeight: 400 }}>
          {formatTime(drive.startedAt)} – {formatTime(drive.endedAt)}
        </span>
      </h1>
      <p className="subtitle">
        {drive.distanceMiles.toFixed(1)} miles · {formatDuration(drive)} ·{" "}
        <span className={`badge ${drive.category}`}>{drive.category}</span>
        {drive.category === "business" && (
          <>
            {" "}
            · {formatMoney(deductionDollars(drive))} deduction at{" "}
            {drive.rateCentsPerMile}¢/mi
          </>
        )}
      </p>

      <MapView route={route} height={380} />

      <h2>Details</h2>
      <div className="panel">
        <DriveEditor drive={drive} />
      </div>
    </main>
  );
}
