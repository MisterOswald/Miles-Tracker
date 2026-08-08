"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { DriveDTO } from "@/lib/drives";

export default function DriveEditor({ drive }: { drive: DriveDTO }) {
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
    <div className="form-grid">
      <label htmlFor="start">Start address</label>
      <input
        id="start"
        value={startAddress}
        onChange={(e) => setStartAddress(e.target.value)}
      />
      <label htmlFor="end">End address</label>
      <input
        id="end"
        value={endAddress}
        onChange={(e) => setEndAddress(e.target.value)}
      />
      <label htmlFor="distance">Distance (miles)</label>
      <input
        id="distance"
        inputMode="decimal"
        value={distance}
        onChange={(e) => setDistance(e.target.value)}
      />
      <label htmlFor="category">Category</label>
      <select
        id="category"
        value={category}
        onChange={(e) => setCategory(e.target.value as DriveDTO["category"])}
      >
        <option value="unclassified">Unclassified</option>
        <option value="business">Business</option>
        <option value="personal">Personal</option>
      </select>
      <label htmlFor="note">Purpose</label>
      <textarea
        id="note"
        rows={2}
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="e.g. Client meeting — Johnson account"
      />
      <div />
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <button className="primary" onClick={save} disabled={busy}>
          Save changes
        </button>
        <button
          onClick={remove}
          disabled={busy}
          style={{ color: "var(--danger)" }}
        >
          Delete drive
        </button>
        {status && (
          <span style={{ color: "var(--text-muted)", fontSize: 13 }}>
            {status}
          </span>
        )}
      </div>
    </div>
  );
}
