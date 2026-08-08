#!/usr/bin/env node
// Applies SQL files in ./migrations in filename order, tracking progress in
// the _migrations table. Reads POSTGRES_URL from the environment, falling
// back to .env.local so `npm run db:migrate` works locally without extra setup.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import postgres from "postgres";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

function loadDotEnvLocal() {
  const file = path.join(root, ".env.local");
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!m) continue;
    const key = m[1];
    let value = m[2];
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

loadDotEnvLocal();

const url = process.env.POSTGRES_URL;
if (!url) {
  console.error(
    "POSTGRES_URL is not set. Export it or add it to web/.env.local."
  );
  process.exit(1);
}

const isLocal = /localhost|127\.0\.0\.1/.test(url);
const sql = postgres(url, {
  max: 1,
  prepare: false,
  ssl: isLocal ? false : "require",
});

try {
  await sql`create table if not exists _migrations (
    name text primary key,
    applied_at timestamptz not null default now()
  )`;

  const applied = new Set(
    (await sql`select name from _migrations`).map((r) => r.name)
  );

  const dir = path.join(root, "migrations");
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  let ran = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const body = fs.readFileSync(path.join(dir, file), "utf8");
    console.log(`Applying ${file}...`);
    await sql.begin(async (tx) => {
      await tx.unsafe(body);
      await tx`insert into _migrations (name) values (${file})`;
    });
    ran += 1;
  }
  console.log(
    ran === 0 ? "Database is up to date." : `Applied ${ran} migration(s).`
  );
} finally {
  await sql.end();
}
