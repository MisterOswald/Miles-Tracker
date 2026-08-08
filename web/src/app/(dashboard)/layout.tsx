import Link from "next/link";
import { redirect } from "next/navigation";
import { isAuthenticated } from "@/lib/auth";
import LogoutButton from "@/components/LogoutButton";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  if (!(await isAuthenticated())) {
    redirect("/login");
  }
  return (
    <div className="shell">
      <header className="topnav">
        <Link href="/" className="brand">
          Miles<span>.</span>
        </Link>
        <nav>
          <Link href="/">Dashboard</Link>
          <Link href="/drives">Drives</Link>
          <Link href="/reports">Reports</Link>
        </nav>
        <div className="spacer" />
        <LogoutButton />
      </header>
      {children}
    </div>
  );
}
