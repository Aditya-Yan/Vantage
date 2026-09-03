import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// React Testing Library's automatic cleanup only registers itself when Vitest
// globals are enabled. This project uses explicit imports (globals: false), so
// cleanup is wired up here instead. Without it, renders accumulate in the DOM
// across tests and queries match duplicates.
afterEach(() => {
  cleanup();
});
