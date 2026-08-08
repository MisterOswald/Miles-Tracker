import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";
import type { DriveDTO } from "./drives";
import { deductionDollars, formatMoney } from "./format";

export interface ReportScope {
  year: number;
  quarter?: number;
  category?: string;
}

export function reportTitle(scope: ReportScope): string {
  const period = scope.quarter ? `Q${scope.quarter} ${scope.year}` : `${scope.year}`;
  return `Mileage Report — ${period}`;
}

function csvEscape(value: string): string {
  if (/[",\n]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

interface ReportRow {
  date: string;
  route: string;
  miles: string;
  category: string;
  purpose: string;
  rate: string;
  deduction: string;
}

function toReportRows(drives: DriveDTO[]): {
  rows: ReportRow[];
  totalMiles: number;
  businessMiles: number;
  totalDeduction: number;
} {
  const sorted = [...drives].sort(
    (a, b) => new Date(a.startedAt).getTime() - new Date(b.startedAt).getTime()
  );
  let totalMiles = 0;
  let businessMiles = 0;
  let totalDeduction = 0;
  const rows = sorted.map((d) => {
    const deduction = deductionDollars(d);
    totalMiles += d.distanceMiles;
    if (d.category === "business") businessMiles += d.distanceMiles;
    totalDeduction += deduction;
    return {
      date: new Date(d.startedAt).toLocaleDateString("en-US", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }),
      route: `${d.startAddress || "Unknown"} → ${d.endAddress || "Unknown"}`,
      miles: d.distanceMiles.toFixed(1),
      category: d.category.charAt(0).toUpperCase() + d.category.slice(1),
      purpose: d.purposeNote,
      rate: d.category === "business" ? `${d.rateCentsPerMile}¢` : "—",
      deduction: d.category === "business" ? formatMoney(deduction) : "—",
    };
  });
  return { rows, totalMiles, businessMiles, totalDeduction };
}

export function buildCSV(drives: DriveDTO[], scope: ReportScope): string {
  const { rows, totalMiles, businessMiles, totalDeduction } =
    toReportRows(drives);
  const header = [
    "Date",
    "Start → End Address",
    "Miles",
    "Category",
    "Purpose",
    "Rate (¢/mi)",
    "Deduction ($)",
  ];
  const lines = [header.join(",")];
  for (const r of rows) {
    lines.push(
      [
        r.date,
        csvEscape(r.route),
        r.miles,
        r.category,
        csvEscape(r.purpose),
        r.rate.replace("¢", ""),
        r.deduction.replace(/[$,—]/g, "") || "0.00",
      ].join(",")
    );
  }
  lines.push("");
  lines.push(`Total miles,,${totalMiles.toFixed(1)},,,,`);
  lines.push(`Business miles,,${businessMiles.toFixed(1)},,,,`);
  lines.push(`Total deduction,,,,,,${totalDeduction.toFixed(2)}`);
  lines.push("");
  lines.push(csvEscape(reportTitle(scope)));
  return lines.join("\r\n");
}

export function buildPDF(drives: DriveDTO[], scope: ReportScope): Uint8Array {
  const { rows, totalMiles, businessMiles, totalDeduction } =
    toReportRows(drives);
  const doc = new jsPDF({ orientation: "landscape", unit: "pt" });
  const pageWidth = doc.internal.pageSize.getWidth();

  doc.setFont("helvetica", "bold");
  doc.setFontSize(18);
  doc.text(reportTitle(scope), 40, 48);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(10);
  doc.setTextColor(90);
  doc.text(
    `Standard mileage method · ${rows.length} drives · Generated ${new Date().toLocaleDateString("en-US")}`,
    40,
    66
  );
  doc.setTextColor(0);

  autoTable(doc, {
    startY: 84,
    head: [
      ["Date", "Start → End Address", "Miles", "Category", "Purpose", "Rate", "Deduction"],
    ],
    body: rows.map((r) => [
      r.date,
      r.route,
      r.miles,
      r.category,
      r.purpose,
      r.rate,
      r.deduction,
    ]),
    foot: [
      ["", "Total miles", totalMiles.toFixed(1), "", "", "", ""],
      ["", "Business miles", businessMiles.toFixed(1), "", "", "", ""],
      ["", "Total deduction", "", "", "", "", formatMoney(totalDeduction)],
    ],
    styles: { fontSize: 8, cellPadding: 4, overflow: "linebreak" },
    headStyles: { fillColor: [30, 41, 59], textColor: 255, fontStyle: "bold" },
    footStyles: { fillColor: [241, 245, 249], textColor: 20, fontStyle: "bold" },
    alternateRowStyles: { fillColor: [248, 250, 252] },
    columnStyles: {
      0: { cellWidth: 62 },
      1: { cellWidth: "auto" },
      2: { cellWidth: 44, halign: "right" },
      3: { cellWidth: 60 },
      4: { cellWidth: 140 },
      5: { cellWidth: 44, halign: "right" },
      6: { cellWidth: 64, halign: "right" },
    },
    didDrawPage: () => {
      doc.setFontSize(8);
      doc.setTextColor(130);
      doc.text(
        `Miles — ${reportTitle(scope)} — page ${doc.getNumberOfPages()}`,
        pageWidth - 40,
        doc.internal.pageSize.getHeight() - 20,
        { align: "right" }
      );
      doc.setTextColor(0);
    },
  });

  return new Uint8Array(doc.output("arraybuffer"));
}
