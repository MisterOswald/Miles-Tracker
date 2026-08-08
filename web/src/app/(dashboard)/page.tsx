import Link from "next/link";
import { sql } from "@/lib/db";
import { formatMoney } from "@/lib/format";

export const dynamic = "force-dynamic";

interface PeriodRow {
  period: number;
  miles: number;
  businessMiles: number;
  personalMiles: number;
  deduction: number;
  count: number;
}

async function loadYearStats(year: number) {
  const [totals] = await sql`
    select
      count(*)::int as count,
      count(*) filter (where category = 'unclassified')::int as unclassified,
      coalesce(sum(distance_miles), 0) as miles,
      coalesce(sum(distance_miles) filter (where category = 'business'), 0) as business_miles,
      coalesce(sum(distance_miles) filter (where category = 'personal'), 0) as personal_miles,
      coalesce(sum(distance_miles * rate_cents_per_mile / 100.0)
        filter (where category = 'business'), 0) as deduction
    from drives
    where deleted_at is null and extract(year from started_at) = ${year}
  `;

  const byPeriod = async (unit: "month" | "quarter"): Promise<PeriodRow[]> => {
    const rows = await sql`
      select
        extract(${sql.unsafe(unit)} from started_at)::int as period,
        count(*)::int as count,
        coalesce(sum(distance_miles), 0) as miles,
        coalesce(sum(distance_miles) filter (where category = 'business'), 0) as business_miles,
        coalesce(sum(distance_miles) filter (where category = 'personal'), 0) as personal_miles,
        coalesce(sum(distance_miles * rate_cents_per_mile / 100.0)
          filter (where category = 'business'), 0) as deduction
      from drives
      where deleted_at is null and extract(year from started_at) = ${year}
      group by 1 order by 1
    `;
    return rows.map((r) => ({
      period: r.period,
      count: r.count,
      miles: Number(r.miles),
      businessMiles: Number(r.business_miles),
      personalMiles: Number(r.personal_miles),
      deduction: Number(r.deduction),
    }));
  };

  const years = await sql`
    select distinct extract(year from started_at)::int as y
    from drives where deleted_at is null order by y desc
  `;

  return {
    totals: {
      count: totals.count as number,
      unclassified: totals.unclassified as number,
      miles: Number(totals.miles),
      businessMiles: Number(totals.business_miles),
      personalMiles: Number(totals.personal_miles),
      deduction: Number(totals.deduction),
    },
    months: await byPeriod("month"),
    quarters: await byPeriod("quarter"),
    years: years.map((r) => r.y as number),
  };
}

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function PeriodTable({
  rows,
  label,
  nameFor,
  year,
}: {
  rows: PeriodRow[];
  label: string;
  nameFor: (p: number) => string;
  year: number;
}) {
  if (rows.length === 0) return null;
  const maxMiles = Math.max(...rows.map((r) => r.miles), 1);
  return (
    <>
      <h2>{label}</h2>
      <table className="data">
        <thead>
          <tr>
            <th>{label === "By quarter" ? "Quarter" : "Month"}</th>
            <th>Volume</th>
            <th className="num">Drives</th>
            <th className="num">Miles</th>
            <th className="num">Business</th>
            <th className="num">Personal</th>
            <th className="num">Deduction</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.period}>
              <td>
                <Link
                  href={`/drives?year=${year}&${label === "By quarter" ? "quarter" : "month"}=${r.period}`}
                >
                  {nameFor(r.period)}
                </Link>
              </td>
              <td>
                <div className="bar">
                  <div style={{ width: `${(r.miles / maxMiles) * 100}%` }} />
                </div>
              </td>
              <td className="num">{r.count}</td>
              <td className="num">{r.miles.toFixed(1)}</td>
              <td className="num">{r.businessMiles.toFixed(1)}</td>
              <td className="num">{r.personalMiles.toFixed(1)}</td>
              <td className="num">{formatMoney(r.deduction)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ year?: string }>;
}) {
  const params = await searchParams;
  const currentYear = new Date().getFullYear();
  const year = Number(params.year) || currentYear;
  const { totals, months, quarters, years } = await loadYearStats(year);
  const yearOptions = years.includes(year)
    ? years
    : [year, ...years].sort((a, b) => b - a);

  return (
    <main>
      <h1>Dashboard</h1>
      <p className="subtitle">
        Mileage summary for{" "}
        <strong>{year}</strong>
        {" · "}
        {yearOptions.map((y) => (
          <Link key={y} href={`/?year=${y}`} style={{ marginRight: 8 }}>
            {y === year ? <strong>{y}</strong> : y}
          </Link>
        ))}
      </p>

      {totals.count === 0 ? (
        <div className="empty">
          <div className="big">🚗</div>
          <p>
            No drives recorded for {year} yet. Drives sync automatically from
            the iPhone app once you sign in there.
          </p>
        </div>
      ) : (
        <>
          <div className="cards">
            <div className="card">
              <div className="label">Total miles</div>
              <div className="value">{totals.miles.toFixed(1)}</div>
              <div className="hint">{totals.count} drives</div>
            </div>
            <div className="card">
              <div className="label">Business miles</div>
              <div className="value" style={{ color: "var(--business)" }}>
                {totals.businessMiles.toFixed(1)}
              </div>
              <div className="hint">
                {totals.miles > 0
                  ? `${Math.round((totals.businessMiles / totals.miles) * 100)}% of total`
                  : "—"}
              </div>
            </div>
            <div className="card">
              <div className="label">Personal miles</div>
              <div className="value" style={{ color: "var(--personal)" }}>
                {totals.personalMiles.toFixed(1)}
              </div>
              <div className="hint">
                {totals.miles > 0
                  ? `${Math.round((totals.personalMiles / totals.miles) * 100)}% of total`
                  : "—"}
              </div>
            </div>
            <div className="card">
              <div className="label">Estimated deduction</div>
              <div className="value">{formatMoney(totals.deduction)}</div>
              <div className="hint">business miles × IRS rate</div>
            </div>
            <div className="card">
              <div className="label">Unclassified</div>
              <div
                className="value"
                style={{
                  color:
                    totals.unclassified > 0
                      ? "var(--unclassified)"
                      : "var(--business)",
                }}
              >
                {totals.unclassified}
              </div>
              <div className="hint">
                {totals.unclassified > 0 ? (
                  <Link href={`/drives?year=${year}&category=unclassified`}>
                    classify now →
                  </Link>
                ) : (
                  "all caught up"
                )}
              </div>
            </div>
          </div>

          <PeriodTable
            rows={quarters}
            label="By quarter"
            nameFor={(q) => `Q${q}`}
            year={year}
          />
          <PeriodTable
            rows={months}
            label="By month"
            nameFor={(m) => MONTH_NAMES[m - 1]}
            year={year}
          />
        </>
      )}
    </main>
  );
}
