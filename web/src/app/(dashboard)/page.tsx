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
        filter (where category = 'business'), 0) as deduction,
      coalesce(avg(rate_cents_per_mile) filter (where category = 'business'), 0) as avg_rate
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
      avgRate: Number(totals.avg_rate),
    },
    months: await byPeriod("month"),
    quarters: await byPeriod("quarter"),
    years: years.map((r) => r.y as number),
  };
}

const MONTH_ABBR = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning 👋";
  if (hour < 18) return "Good afternoon 👋";
  return "Good evening 👋";
}

function rateLabel(cents: number): string {
  if (!cents) return "";
  return cents % 1 === 0 ? `${cents.toFixed(0)}¢` : `${cents.toFixed(1)}¢`;
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ year?: string }>;
}) {
  const params = await searchParams;
  const now = new Date();
  const currentYear = now.getFullYear();
  const year = Number(params.year) || currentYear;
  const { totals, months, quarters, years } = await loadYearStats(year);
  const yearOptions = (
    years.includes(year) ? years : [year, ...years]
  ).sort((a, b) => b - a);

  const maxQuarterMiles = Math.max(...quarters.map((q) => q.miles), 1);
  const maxMonthMiles = Math.max(...months.map((m) => m.miles), 1);
  const currentQuarter =
    year === currentYear ? Math.floor(now.getMonth() / 3) + 1 : 0;

  return (
    <main>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 24,
          flexWrap: "wrap",
          gap: 12,
        }}
      >
        <div>
          <h1>{greeting()}</h1>
          <p className="subtitle" style={{ margin: 0 }}>
            Here&apos;s your mileage for {year}
          </p>
        </div>
        <div className="seg">
          {yearOptions.slice(0, 4).map((y) => (
            <Link key={y} href={`/?year=${y}`} className={y === year ? "on" : ""}>
              {y}
            </Link>
          ))}
        </div>
      </div>

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
          <div className="stat-grid">
            <div className="card hero">
              <div className="label">Estimated deduction</div>
              <div className="value">{formatMoney(totals.deduction)}</div>
              <div className="hint">
                {totals.businessMiles.toLocaleString("en-US", {
                  maximumFractionDigits: 1,
                })}{" "}
                business miles
                {totals.avgRate > 0 && <> × {rateLabel(totals.avgRate)}</>}
              </div>
            </div>
            <div className="card">
              <div className="label">
                <span className="chip" style={{ background: "var(--accent)" }} />
                Total miles
              </div>
              <div className="value">
                {totals.miles.toLocaleString("en-US", { maximumFractionDigits: 1 })}
              </div>
              <div className="hint">{totals.count} drives</div>
            </div>
            <div className="card">
              <div className="label">
                <span className="chip" style={{ background: "var(--business)" }} />
                Business
              </div>
              <div className="value">
                {totals.businessMiles.toLocaleString("en-US", {
                  maximumFractionDigits: 1,
                })}
              </div>
              <div className="hint">
                {totals.miles > 0
                  ? `${Math.round((totals.businessMiles / totals.miles) * 100)}% of total`
                  : "—"}
              </div>
            </div>
            <div className="card">
              <div className="label">
                <span className="chip" style={{ background: "var(--personal)" }} />
                Personal
              </div>
              <div className="value">
                {totals.personalMiles.toLocaleString("en-US", {
                  maximumFractionDigits: 1,
                })}
              </div>
              <div className="hint">
                {totals.miles > 0
                  ? `${Math.round((totals.personalMiles / totals.miles) * 100)}% of total`
                  : "—"}
              </div>
            </div>
          </div>

          <div className="panel-grid">
            <div className="panel">
              <h2>By quarter</h2>
              <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
                {quarters.map((q) => (
                  <div key={q.period}>
                    <div
                      style={{
                        display: "flex",
                        justifyContent: "space-between",
                        fontSize: 13,
                        marginBottom: 6,
                      }}
                    >
                      <Link
                        href={`/drives?year=${year}&quarter=${q.period}`}
                        style={{ fontWeight: 600, color: "var(--text)" }}
                      >
                        Q{q.period}
                      </Link>
                      <span style={{ color: "var(--muted)" }}>
                        {q.miles.toFixed(1)} mi ·{" "}
                        <span style={{ color: "var(--text)", fontWeight: 700 }}>
                          {formatMoney(q.deduction)}
                        </span>
                      </span>
                    </div>
                    <div className="qbar-track">
                      <div
                        className="qbar-fill"
                        style={{ width: `${(q.miles / maxQuarterMiles) * 100}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              <div
                style={{
                  marginTop: 20,
                  paddingTop: 16,
                  borderTop: "1px solid #f0f0f7",
                  display: "flex",
                  justifyContent: "space-between",
                  fontSize: 13,
                }}
              >
                <span style={{ color: "var(--muted)" }}>Unclassified drives</span>
                {totals.unclassified > 0 ? (
                  <Link
                    href={`/drives?year=${year}&category=unclassified`}
                    style={{ fontWeight: 700 }}
                  >
                    {totals.unclassified} — classify now →
                  </Link>
                ) : (
                  <span style={{ color: "var(--business)", fontWeight: 700 }}>
                    All caught up
                  </span>
                )}
              </div>
            </div>

            <div className="panel">
              <h2>By month</h2>
              <div className="month-chart">
                {months.map((m) => (
                  <div key={m.period} className="month-col">
                    <div className="v">{Math.round(m.miles)}</div>
                    <div
                      className="bar"
                      style={{
                        height: `${Math.max((m.miles / maxMonthMiles) * 100, 3)}%`,
                        background:
                          currentQuarter > 0 &&
                          Math.floor((m.period - 1) / 3) + 1 === currentQuarter
                            ? "var(--accent)"
                            : "var(--bar-dim)",
                      }}
                    />
                    <div className="n">{MONTH_ABBR[m.period - 1]}</div>
                  </div>
                ))}
              </div>
              <div className="legend">
                <span>
                  <span className="sw" style={{ background: "var(--accent)" }} />
                  This quarter
                </span>
                <span>
                  <span className="sw" style={{ background: "var(--bar-dim)" }} />
                  Earlier
                </span>
              </div>
            </div>
          </div>
        </>
      )}
    </main>
  );
}
