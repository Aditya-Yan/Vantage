import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";

import Home from "../app/page";

test("renders the dashboard heading", () => {
  render(<Home />);

  expect(
    screen.getByRole("heading", { level: 1, name: "Vantage" }),
  ).toBeDefined();
});

test("renders the current phase status", () => {
  render(<Home />);

  expect(
    screen.getByRole("heading", { name: /Phase 1 — Development foundation/ }),
  ).toBeDefined();
});

test("renders a placeholder for every pipeline counter", () => {
  render(<Home />);

  for (const label of [
    "Target companies",
    "Discoveries",
    "Canonical jobs",
    "Recruiters",
  ]) {
    expect(screen.getByText(label)).toBeDefined();
  }
});

test("labels the counters as having no data source", () => {
  // docs/METRICS.md forbids presenting an unsupported number as a measurement.
  // Until Phase 2 connects a database, the page must say so plainly.
  render(<Home />);

  expect(screen.getByText(/No data source connected/)).toBeDefined();
});

test("does not render a fabricated zero as a metric value", () => {
  const { container } = render(<Home />);

  const values = Array.from(container.querySelectorAll("dd")).map((el) =>
    el.textContent?.trim(),
  );

  expect(values).toHaveLength(4);
  for (const value of values) {
    expect(value).not.toBe("0");
  }
});
