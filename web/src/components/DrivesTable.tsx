"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { DriveDTO } from "@/lib/drives";
import {
  deductionDollars,
  formatDate,
  formatMiles,
  formatMoney,
  formatTime,
} from "@/lib/format";

interface Totals {
  count: number;
  miles: number;
  businessMiles: number;
  deduction: number;
}

export default function DrivesTable() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const year = searchParams.get("year") ?? String(new Date().getFullYear());
  const month = searchParams.get("month") ?? "";
  const quarter = searchParams.get("quarter") ?? "";
  const category = searchParams.get("category") ?? "";

  const [drives, setDrives] = useState<DriveDTO[] | null>(null);
  const [totals, setTotals] = useState<Totals | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const params = new URLSearchParams({ year });
    if (month) params.set("month", month);
    if (quarter) params.set("quarter", quarter);
    if (category) params.set("category", category);
    try {
      const res = await fetch(`/api/drives?${params}`, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      setDrives(body.drives);
      setTotals(body.totals);
    } catch {
      setError("Could not load drives. Check your connection and try again.");
      setDrives([]);
    }
  }, [year, month, quarter, category]);

  useEffect(() => {
    load();
  }, [load]);

  function setFilter(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) params.set(key, value);
    else params.delete(key);
    if (key === "month" && value) params.delete("quarter");
    if (key === "quarter" && value) params.delete("month");
    router.replace(`/drives?${params}`);
  }

  async function patchDrive(id: string, patch: Partial<DriveDTO>) {
    setDrives(
      (prev) =>
        prev?.map((d) => (d.id === id ? { ...d, ...patch } : d)) ?? prev
    );
    const res = await fetch(`/api/drives/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    if (!res.ok) {
      setError("Saving failed — reloading.");
      await load();
    }
  }

  const yearNum = Number(year);
  const yearOptions = Array.from(
    { length: 6 },
    (_, i) => new Date().getFullYear() - i
  );
  if (!yearOptions.includes(yearNum) && Number.isInteger(yearNum)) {
    yearOptions.push(yearNum);
    yearOptions.sort((a, b) => b - a);
  }

  return (
    <>
      <div className="filters">
        <select value={year} onChange={(e) => setFilter("year", e.target.value)}>
          {yearOptions.map((y) => (
            <option key={y} value={y}>
              {y}
            </option>
          ))}
        </select>
        <select
          value={quarter}
          onChange={(e) => setFilter("quarter", e.target.value)}
        >
          <option value="">All quarters</option>
          {[1, 2, 3, 4].map((q) => (
            <option key={q} value={q}>
              Q{q}
            </option>
          ))}
        </select>
        <select
          value={month}
          onChange={(e) => setFilter("month", e.target.value)}
        >
          <option value="">All months</option>
          {Array.from({ length: 12 }, (_, i) => (
            <option key={i + 1} value={i + 1}>
              {new Date(2000, i, 1).toLocaleString("en-US", { month: "long" })}
            </option>
          ))}
        </select>
        <select
          value={category}
          onChange={(e) => setFilter("category", e.target.value)}
        >
          <option value="">All categories</option>
          <option value="business">Business</option>
          <option value="personal">Personal</option>
          <option value="unclassified">Unclassified</option>
        </select>
        {totals && (
          <span style={{ color: "var(--text-muted)", fontSize: 13 }}>
            {totals.count} drives · {formatMiles(totals.miles)} ·{" "}
            {formatMoney(totals.deduction)} deduction
          </span>
        )}
      </div>

      {error && <div className="error-text">{error}</div>}

      {drives === null ? (
        <div className="empty">Loading…</div>
      ) : drives.length === 0 ? (
        <div className="empty">
          <div className="big">🗺️</div>
          <p>No drives match these filters.</p>
        </div>
      ) : (
        <table className="data">
          <thead>
            <tr>
              <th>Date</th>
              <th>Route</th>
              <th className="num">Miles</th>
              <th>Category</th>
              <th>Purpose</th>
              <th className="num">Deduction</th>
            </tr>
          </thead>
          <tbody>
            {drives.map((d) => (
              <DriveRow key={d.id} drive={d} onPatch={patchDrive} />
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

function DriveRow({
  drive,
  onPatch,
}: {
  drive: DriveDTO;
  onPatch: (id: string, patch: Partial<DriveDTO>) => Promise<void>;
}) {
  const [note, setNote] = useState(drive.purposeNote);
  const noteTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => setNote(drive.purposeNote), [drive.purposeNote]);

  function onNoteChange(value: string) {
    setNote(value);
    if (noteTimer.current) clearTimeout(noteTimer.current);
    noteTimer.current = setTimeout(() => {
      onPatch(drive.id, { purposeNote: value });
    }, 700);
  }

  return (
    <tr>
      <td style={{ whiteSpace: "nowrap" }}>
        <Link href={`/drives/${drive.id}`}>{formatDate(drive.startedAt)}</Link>
        <div style={{ color: "var(--text-muted)", fontSize: 12 }}>
          {formatTime(drive.startedAt)} – {formatTime(drive.endedAt)}
        </div>
      </td>
      <td>
        <div>{drive.startAddress || "Unknown start"}</div>
        <div style={{ color: "var(--text-muted)", fontSize: 12 }}>
          → {drive.endAddress || "Unknown end"}
        </div>
      </td>
      <td className="num">{drive.distanceMiles.toFixed(1)}</td>
      <td style={{ whiteSpace: "nowrap" }}>
        <button
          className={`small ${drive.category === "business" ? "active-business" : ""}`}
          onClick={() => onPatch(drive.id, { category: "business" })}
        >
          Business
        </button>{" "}
        <button
          className={`small ${drive.category === "personal" ? "active-personal" : ""}`}
          onClick={() => onPatch(drive.id, { category: "personal" })}
        >
          Personal
        </button>
      </td>
      <td>
        <input
          className="note-input"
          placeholder="Purpose…"
          value={note}
          onChange={(e) => onNoteChange(e.target.value)}
        />
      </td>
      <td className="num">
        {drive.category === "business"
          ? formatMoney(deductionDollars(drive))
          : "—"}
      </td>
    </tr>
  );
}
