import { sql } from "@/lib/db";
import ReportDownloads from "@/components/ReportDownloads";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const rows = await sql`
    select distinct extract(year from started_at)::int as y
    from drives where deleted_at is null order by y desc
  `;
  const years = rows.map((r) => r.y as number);
  if (years.length === 0) years.push(new Date().getFullYear());

  return (
    <main>
      <h1>Reports</h1>
      <p className="subtitle" style={{ maxWidth: 560 }}>
        CSV and PDF reports for your CPA — formatted for an S-Corp
        accountable-plan reimbursement file.
      </p>
      <div className="panel" style={{ padding: 24 }}>
        <ReportDownloads years={years} />
      </div>
    </main>
  );
}
