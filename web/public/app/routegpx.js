// A saved route as a GPX file, for other apps and devices (CrewNerd, Garmin, Strava) and as a backup
// (owner, 14 Nov 2026): one track with the turning points, and the way back when rowed out and back.
// The app's RouteGPX.swift writes the same file.

const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function gpxText(route) {
  const points = route.outAndBack ? [...route.points, ...route.points.slice(0, -1).reverse()] : route.points;
  const name = escape(route.name);
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Row Frog" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${name}</name></metadata>
  <trk>
    <name>${name}</name>
    <type>rowing</type>
    <trkseg>
${points.map((p) => `      <trkpt lat="${p.lat.toFixed(5)}" lon="${p.lon.toFixed(5)}"/>`).join("\n")}
    </trkseg>
  </trk>
</gpx>
`;
}

/** "Rund um die Roseninsel.gpx": the name without characters file systems refuse. */
export function gpxFileName(route) {
  const base = route.name.replace(/[/\\:*?"<>|\u0000-\u001f\u007f]/g, " ").trim();
  return `${base ? base.slice(0, 80) : "Route"}.gpx`;
}

/** Downloads the route's GPX file. */
export function downloadGpx(route) {
  const url = URL.createObjectURL(new Blob([gpxText(route)], { type: "application/gpx+xml" }));
  const a = Object.assign(document.createElement("a"), { href: url, download: gpxFileName(route) });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
