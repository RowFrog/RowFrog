// The Home Screen web app opens straight on the forecasts, as the app does (owner, 15 Nov 2026). A web app added
// to the Home Screen from this page starts here each time it is opened again after being closed, and showed
// this welcome page every time; it now goes on to /app/ at once. In a browser tab the page stays as it is.
const homeScreen = navigator.standalone === true || matchMedia("(display-mode: standalone)").matches;
if (homeScreen) location.replace(`/app/${location.hash}`);
