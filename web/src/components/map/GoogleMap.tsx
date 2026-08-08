"use client";

// Google Maps fallback, used only when NEXT_PUBLIC_GOOGLE_MAPS_API_KEY is set.
import { useEffect, useRef } from "react";
import type { MapViewProps } from "./MapView";

declare global {
  interface Window {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    google?: any;
    __gmapsLoading?: Promise<void>;
  }
}

function loadGoogleMaps(apiKey: string): Promise<void> {
  if (window.google?.maps) return Promise.resolve();
  if (window.__gmapsLoading) return window.__gmapsLoading;
  window.__gmapsLoading = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&loading=async`;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("Failed to load Google Maps"));
    document.head.appendChild(script);
  });
  return window.__gmapsLoading;
}

export default function GoogleMap({ route, height = 320 }: MapViewProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey || !ref.current || route.length === 0) return;
    let cancelled = false;

    loadGoogleMaps(apiKey)
      .then(() => {
        if (cancelled || !ref.current) return;
        const g = window.google.maps;
        const map = new g.Map(ref.current, {
          disableDefaultUI: true,
          zoomControl: true,
        });
        const path = route.map(([lat, lng]) => ({ lat, lng }));
        const boundsObj = new g.LatLngBounds();
        for (const p of path) boundsObj.extend(p);
        map.fitBounds(boundsObj, 40);
        new g.Polyline({
          path,
          map,
          strokeColor: "#1d5fd6",
          strokeWeight: 4,
          strokeOpacity: 0.85,
        });
        new g.Marker({ position: path[0], map, label: "A" });
        new g.Marker({ position: path[path.length - 1], map, label: "B" });
      })
      .catch((err) => console.error(err));

    return () => {
      cancelled = true;
    };
  }, [route]);

  return <div ref={ref} style={{ height, width: "100%" }} />;
}
