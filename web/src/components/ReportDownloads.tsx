"use client";

import { useState } from "react";

export default function ReportDownloads({ years }: { years: number[] }) {
  const [year, setYear] = useState(years[0]);
  const [quarter, setQuarter] = useState("");
  const [category, setCategory] = useState("");

  const params = new URLSearchParams({ year: String(year) });
  if (quarter) params.set("quarter", quarter);
  if (category) params.set("category", category);

  return (
    <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
      <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
        {years.map((y) => (
          <option key={y} value={y}>
            {y}
          </option>
        ))}
      </select>
      <select value={quarter} onChange={(e) => setQuarter(e.target.value)}>
        <option value="">Full year</option>
        {[1, 2, 3, 4].map((q) => (
          <option key={q} value={q}>
            Q{q}
          </option>
        ))}
      </select>
      <select value={category} onChange={(e) => setCategory(e.target.value)}>
        <option value="">All categories</option>
        <option value="business">Business only</option>
        <option value="personal">Personal only</option>
      </select>
      <a className="btn primary" href={`/api/export/pdf?${params}`} download>
        Download PDF
      </a>
      <a className="btn" href={`/api/export/csv?${params}`} download>
        Download CSV
      </a>
    </div>
  );
}
