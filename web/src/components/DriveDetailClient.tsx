"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import type { DriveDTO } from "@/lib/drives";
import type { LatLng } from "@/lib/polyline";
import {
  deductionDollars,
  formatDate,
  formatDuration,
  formatMoney,
  formatTime,
} from "@/lib/format";
import MapView from "@/components/map/MapView";

function rateLabel(cents: number): string {
  return cents % 1 === 0 ? `${cents.toFixed(0)}¢` : `${cents.toFixed(1)}¢`;
}

export default function DriveDetailClient({
  drive,
  route,
}: {
  drive: DriveDTO;
  route: LatLng[];
}) {
  const router = useRouter();
  const [startAddress, setStartAddress] = useState(drive.startAddress);
  const [endAddress, setEndAddress] = useState(drive.endAddress);
  const [distance, setDistance] = useState(String(drive.distanceMiles));
  const [category, setCategory] = useState(drive.category);
  const [note, setNote] = useState(drive.purposeNote);
  const [status, setStatus] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    const miles = Number(distance);
    if (!Number.isFinite(miles) || miles < 0) {
      setStatus("Distance must be a non-negative number.");
      return;
    }
    setBusy(true);
    setStatus(null);
    const res = await fetch(`/api/drives/${drive.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        startAddress,
        endAddress,
        distanceMiles: miles,
        category,
        purposeNote: note,
      }),
    });
    setBusy(false);
    if (res.ok) {
      setStatus("Saved.");
      router.refresh();
    } else {
      setStatus("Save failed — try again.");
    }
  }

  async function remove() {
    if (!confirm("Delete this drive? It will also be removed from the phone on next sync.")) {
      return;
    }
    setBusy(true);
    const res = await fetch(`/api/drives/${drive.id}`, { method: "DELETE" });
    setBusy(false);
    if (res.ok) {
      router.push("/drives");
      router.refresh();
    } else {
      setStatus("Delete failed — try again.");
    }
  }

  return (
    <main>
      <Link href="/drives" style={{ fontSize: 13, fontWeight: 700 }}>
        ← All drives
      </Link>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          margin: "10px 0 20px",
          flexWrap: "wrap",
          gap: 12,
        }}
      >
        <div>
          <h1>
            {formatDate(drive.startedAt)}{" "}
            <span style={{ color: "var(--muted)", fontWeight: 600, fontSize: 17 }}>
              {formatTime(drive.startedAt)} – {formatTime(drive.endedAt)}
            </span>
          </h1>
          <p className="subtitle" style={{ margin: 0 }}>
            {drive.distanceMiles.toFixed(1)} miles · {formatDuration(drive)} ·{" "}
            <span className={`badge ${drive.category}`}>
              {drive.category.charAt(0).toUpperCase() + drive.category.slice(1)}
            </span>
            {drive.category === "business" && (
              <>
                {" "}
                ·{" "}
                <strong style={{ color: "var(--business)" }}>
                  {formatMoney(deductionDollars(drive))}
                </strong>{" "}
                at {rateLabel(drive.rateCentsPerMile)}/mi
              </>
            )}
          </p>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          {status && (
            <span style={{ fontSize: 13, color: "var(--muted)" }}>{status}</span>
          )}
          <button className="btn primary" onClick={save} disabled={busy}>
            Save changes
          </button>
          <button className="btn danger-ghost" onClick={remove} disabled={busy}>
            Delete
          </button>
        </div>
      </div>

      <div className="detail-grid">
        <div className="map-card">
          <MapView route={route} height={440} />
        </div>
        <div className="panel">
          <h2>Details</h2>
          <div className="field">
            <div className="field-label">Start address</div>
            <input
              value={startAddress}
              onChange={(e) => setStartAddress(e.target.value)}
            />
          </div>
          <div className="field">
            <div className="field-label">End address</div>
            <input
              value={endAddress}
              onChange={(e) => setEndAddress(e.target.value)}
            />
          </div>
          <div className="field">
            <div className="field-label">Distance (miles)</div>
            <input
              inputMode="decimal"
              value={distance}
              onChange={(e) => setDistance(e.target.value)}
            />
          </div>
          <div className="field">
            <div className="field-label">Category</div>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value as DriveDTO["category"])}
            >
              <option value="unclassified">Unclassified</option>
              <option value="business">Business</option>
              <option value="personal">Personal</option>
            </select>
          </div>
          <div className="field">
            <div className="field-label">Purpose</div>
            <textarea
              rows={2}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="e.g. Client meeting — Johnson account"
            />
          </div>
        </div>
      </div>
    </main>
  );
}
