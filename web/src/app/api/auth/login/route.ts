import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  SESSION_COOKIE,
  issueApiToken,
  issueSessionToken,
  verifyCredentials,
} from "@/lib/auth";

const bodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export async function POST(req: NextRequest) {
  let body: z.infer<typeof bodySchema>;
  try {
    body = bodySchema.parse(await req.json());
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  try {
    if (!verifyCredentials(body.email, body.password)) {
      return NextResponse.json(
        { error: "Invalid email or password" },
        { status: 401 }
      );
    }
  } catch (err) {
    console.error("Auth misconfiguration:", err);
    return NextResponse.json(
      { error: "Server auth is not configured" },
      { status: 500 }
    );
  }

  const [apiToken, sessionToken] = await Promise.all([
    issueApiToken(),
    issueSessionToken(),
  ]);

  const res = NextResponse.json({ token: apiToken });
  res.cookies.set(SESSION_COOKIE, sessionToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });
  return res;
}
