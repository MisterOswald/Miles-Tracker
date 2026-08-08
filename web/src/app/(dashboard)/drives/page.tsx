import { Suspense } from "react";
import DrivesTable from "@/components/DrivesTable";

export const dynamic = "force-dynamic";

export default function DrivesPage() {
  return (
    <main>
      <h1>Drives</h1>
      <p className="subtitle">
        Filter, reclassify, and annotate drives. Changes sync back to the
        iPhone app.
      </p>
      <Suspense>
        <DrivesTable />
      </Suspense>
    </main>
  );
}
