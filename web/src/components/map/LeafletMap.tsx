"use client";

import { MapContainer, TileLayer, Polyline, CircleMarker } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import type { MapViewProps } from "./MapView";
import type { LatLng } from "@/lib/polyline";

function bounds(route: LatLng[]): [[number, number], [number, number]] {
  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLng = Infinity;
  let maxLng = -Infinity;
  for (const [lat, lng] of route) {
    minLat = Math.min(minLat, lat);
    maxLat = Math.max(maxLat, lat);
    minLng = Math.min(minLng, lng);
    maxLng = Math.max(maxLng, lng);
  }
  const padLat = Math.max((maxLat - minLat) * 0.15, 0.002);
  const padLng = Math.max((maxLng - minLng) * 0.15, 0.002);
  return [
    [minLat - padLat, minLng - padLng],
    [maxLat + padLat, maxLng + padLng],
  ];
}

export default function LeafletMap({ route, height = 320 }: MapViewProps) {
  const start = route[0];
  const end = route[route.length - 1];
  return (
    <MapContainer
      bounds={bounds(route)}
      style={{ height, width: "100%" }}
      scrollWheelZoom={false}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Polyline
        positions={route}
        pathOptions={{ color: "#1d5fd6", weight: 4, opacity: 0.85 }}
      />
      <CircleMarker
        center={start}
        radius={7}
        pathOptions={{ color: "#fff", weight: 2, fillColor: "#157347", fillOpacity: 1 }}
      />
      <CircleMarker
        center={end}
        radius={7}
        pathOptions={{ color: "#fff", weight: 2, fillColor: "#c0392b", fillOpacity: 1 }}
      />
    </MapContainer>
  );
}
