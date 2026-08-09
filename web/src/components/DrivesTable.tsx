"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { DriveDTO } from "@/lib/drives";
import {
  deductionDollars,
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
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          marginBottom: 20,
          flexWrap: "wrap",
          gap: 12,
        }}
      >
        <div>
          <h1>Drives</h1>
          <p className="subtitle" style={{ margin: 0 }}>
            {totals ? (
              <>
                {totals.count} drives · {totals.miles.toFixed(1)} mi ·{" "}
                <strong style={{ color: "var(--text)" }}>
                  {formatMoney(totals.deduction)}
                </strong>{" "}
                deduction
              </>
            ) : (
              "Filter, reclassify, and annotate drives."
            )}
          </p>
        </div>
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
        </div>
      </div>

      {error && <div className="error-text" style={{ marginBottom: 12 }}>{error}</div>}

      {drives === null ? (
        <div className="empty">Loading…</div>
      ) : drives.length === 0 ? (
        <div className="empty">
          <div className="big">🗺️</div>
          <p>No drives match these filters.</p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {drives.map((d) => (
            <DriveCard key={d.id} drive={d} onPatch={patchDrive} />
          ))}
        </div>
      )}
    </>
  );
}

function DriveCard({
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

  const dateShort = new Date(drive.startedAt).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });

  return (
    <div className="drive-card">
      <div className="when">
        <Link href={`/drives/${drive.id}`}>
          <div className="d" style={{ color: "var(--text)" }}>
            {dateShort}
          </div>
        </Link>
        <div className="t">{formatTime(drive.startedAt)}</div>
      </div>
      <div className="route">
        <Link href={`/drives/${drive.id}`} style={{ color: "var(--text)" }}>
          <div className="r">
            {(drive.startAddress || "Unknown") + " → " + (drive.endAddress || "Unknown")}
          </div>
        </Link>
        <input
          placeholder="Add a purpose…"
          value={note}
          onChange={(e) => onNoteChange(e.target.value)}
        />
      </div>
      <div className="mi">
        {drive.distanceMiles.toFixed(1)}
        <span> mi</span>
      </div>
      <div style={{ display: "flex", gap: 6, flexShrink: 0 }}>
        <button
          className={`cat-pill business ${drive.category === "business" ? "on" : ""}`}
          onClick={() => onPatch(drive.id, { category: "business" })}
        >
          Business
        </button>
        <button
          className={`cat-pill personal ${drive.category === "personal" ? "on" : ""}`}
          onClick={() => onPatch(drive.id, { category: "personal" })}
        >
          Personal
        </button>
      </div>
      <div className="ded">
        {drive.category === "business" ? formatMoney(deductionDollars(drive)) : ""}
      </div>
    </div>
  );
}
