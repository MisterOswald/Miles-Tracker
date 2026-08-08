"use client";

// Map abstraction: renders Leaflet + OpenStreetMap by default (free, no API
// key). If NEXT_PUBLIC_GOOGLE_MAPS_API_KEY is configured, renders Google Maps
// instead. Both implementations accept the same props.
import dynamic from "next/dynamic";
import type { LatLng } from "@/lib/polyline";

export interface MapViewProps {
  route: LatLng[];
  height?: number;
}

const LeafletMap = dynamic(() => import("./LeafletMap"), {
  ssr: false,
  loading: () => <MapPlaceholder height={320} />,
});
const GoogleMap = dynamic(() => import("./GoogleMap"), {
  ssr: false,
  loading: () => <MapPlaceholder height={320} />,
});

function MapPlaceholder({ height }: { height: number }) {
  return (
    <div
      style={{
        height,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "var(--text-muted)",
        background: "#eef1f5",
      }}
    >
      Loading map…
    </div>
  );
}

export default function MapView({ route, height = 320 }: MapViewProps) {
  if (route.length === 0) {
    return (
      <div className="map-frame">
        <div
          style={{
            height,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "var(--text-muted)",
            background: "#eef1f5",
          }}
        >
          No GPS route recorded for this drive.
        </div>
      </div>
    );
  }
  const useGoogle = Boolean(process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY);
  return (
    <div className="map-frame">
      {useGoogle ? (
        <GoogleMap route={route} height={height} />
      ) : (
        <LeafletMap route={route} height={height} />
      )}
    </div>
  );
}
