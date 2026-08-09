"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";

const NAV = [
  { href: "/", label: "Dashboard" },
  { href: "/drives", label: "Drives" },
  { href: "/reports", label: "Reports" },
];

export default function Sidebar({ userEmail }: { userEmail: string }) {
  const pathname = usePathname();
  const router = useRouter();

  function isActive(href: string) {
    if (href === "/") return pathname === "/";
    return pathname.startsWith(href);
  }

  const initial = (userEmail || "M").charAt(0).toUpperCase();
  const shortName = userEmail.includes("@")
    ? userEmail.slice(0, userEmail.indexOf("@"))
    : userEmail || "You";

  return (
    <aside className="sidebar">
      <Link href="/" className="brand">
        <div className="brand-mark">M</div>
        <div className="brand-name">Miles</div>
      </Link>
      {NAV.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          className={`nav-item ${isActive(item.href) ? "active" : ""}`}
        >
          <div className="dot" />
          {item.label}
        </Link>
      ))}
      <div className="spacer" />
      <div className="user-card">
        <div className="avatar">{initial}</div>
        <div className="who">{shortName}</div>
        <button
          onClick={async () => {
            await fetch("/api/auth/logout", { method: "POST" });
            router.push("/login");
            router.refresh();
          }}
        >
          Out
        </button>
      </div>
    </aside>
  );
}
