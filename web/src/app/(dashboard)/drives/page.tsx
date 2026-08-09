import { Suspense } from "react";
import DrivesTable from "@/components/DrivesTable";

export const dynamic = "force-dynamic";

export default function DrivesPage() {
  return (
    <main>
      <Suspense>
        <DrivesTable />
      </Suspense>
    </main>
  );
}
