import { redirect } from "next/navigation";
import { isAuthenticated } from "@/lib/auth";
import Sidebar from "@/components/Sidebar";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  if (!(await isAuthenticated())) {
    redirect("/login");
  }
  return (
    <div className="app-shell">
      <Sidebar userEmail={process.env.MILES_EMAIL ?? ""} />
      <div className="content">{children}</div>
    </div>
  );
}
