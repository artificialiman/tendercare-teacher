// Client-only: the app reads this device's own storage (localStorage) from its
// first line, and everything it shows is bundled, so there is nothing for a
// server to render or fetch.
export const ssr = false;
