import { SignJWT, jwtVerify } from "jose";
import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

export const SESSION_COOKIE = "miles_session";

function secretKey(): Uint8Array {
  const secret = process.env.AUTH_SECRET;
  if (!secret || secret.length < 16) {
    throw new Error("AUTH_SECRET must be set (16+ characters)");
  }
  return new TextEncoder().encode(secret);
}

export function verifyCredentials(email: string, password: string): boolean {
  const expectedEmail = process.env.MILES_EMAIL;
  const passwordHash = process.env.MILES_PASSWORD_HASH;
  if (!expectedEmail || !passwordHash) {
    throw new Error("MILES_EMAIL and MILES_PASSWORD_HASH must be set");
  }
  if (email.trim().toLowerCase() !== expectedEmail.trim().toLowerCase()) {
    return false;
  }
  return bcrypt.compareSync(password, passwordHash);
}

/** Long-lived bearer token for the iOS app (stored in the Keychain). */
export async function issueApiToken(): Promise<string> {
  return new SignJWT({ scope: "api" })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject("miles-user")
    .setIssuedAt()
    .setExpirationTime("5y")
    .sign(secretKey());
}

/** Shorter-lived token used as the web session cookie. */
export async function issueSessionToken(): Promise<string> {
  return new SignJWT({ scope: "web" })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject("miles-user")
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(secretKey());
}

export async function verifyToken(token: string): Promise<boolean> {
  try {
    await jwtVerify(token, secretKey());
    return true;
  } catch {
    return false;
  }
}

/**
 * Auth check for API route handlers. Accepts either an
 * `Authorization: Bearer <token>` header (iOS) or the session cookie (web).
 * Returns null when authorized, or a 401 response to return as-is.
 */
export async function requireAuth(
  req: NextRequest
): Promise<NextResponse | null> {
  const header = req.headers.get("authorization");
  if (header?.startsWith("Bearer ")) {
    if (await verifyToken(header.slice(7))) return null;
  }
  const cookie = req.cookies.get(SESSION_COOKIE)?.value;
  if (cookie && (await verifyToken(cookie))) return null;
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}

/** Auth check for server components / pages. */
export async function isAuthenticated(): Promise<boolean> {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  return token ? verifyToken(token) : false;
}
