import postgres from "postgres";

type Sql = ReturnType<typeof postgres>;

declare global {
  // eslint-disable-next-line no-var
  var __milesSql: Sql | undefined;
}

function createClient(): Sql {
  const url = process.env.POSTGRES_URL;
  if (!url) {
    throw new Error("POSTGRES_URL is not set");
  }
  const isLocal = /localhost|127\.0\.0\.1/.test(url);
  // prepare: false keeps this compatible with transaction-mode poolers
  // (Supabase pgbouncer, Neon pooled endpoints).
  return postgres(url, {
    max: 1,
    prepare: false,
    ssl: isLocal ? false : "require",
  });
}

function getClient(): Sql {
  if (!globalThis.__milesSql) {
    globalThis.__milesSql = createClient();
  }
  return globalThis.__milesSql;
}

// Lazy proxy so importing this module never connects (or requires env vars)
// at build time — the client is created on first query.
export const sql: Sql = new Proxy(function () {} as unknown as Sql, {
  apply(_target, _thisArg, args) {
    return Reflect.apply(getClient() as unknown as Function, undefined, args);
  },
  get(_target, prop) {
    const client = getClient() as unknown as Record<PropertyKey, unknown>;
    const value = client[prop];
    return typeof value === "function" ? (value as Function).bind(client) : value;
  },
});
