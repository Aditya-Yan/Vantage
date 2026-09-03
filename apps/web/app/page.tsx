import { Button } from "@/components/ui/button";

/**
 * Placeholder dashboard.
 *
 * Phase 9 builds the real interface. This exists to prove the toolchain works
 * end to end: Next.js, Tailwind, shadcn/ui, TypeScript strict mode, and Vitest.
 *
 * The counters below are structural placeholders, not measurements. There is
 * no database until Phase 2, so they are explicitly labeled as having no data
 * source. docs/METRICS.md forbids presenting an unsupported number as a
 * metric, and a bare zero styled like a statistic would be exactly that.
 */

const PLACEHOLDER_COUNTERS = [
  { label: "Target companies", key: "companies" },
  { label: "Discoveries", key: "discoveries" },
  { label: "Canonical jobs", key: "jobs" },
  { label: "Recruiters", key: "recruiters" },
] as const;

export default function Home() {
  return (
    <div className="flex flex-1 flex-col items-center bg-zinc-50 font-sans dark:bg-zinc-950">
      <main className="w-full max-w-3xl flex-1 px-6 py-16 sm:px-10">
        <header className="mb-10">
          <h1 className="text-2xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
            Vantage
          </h1>
          <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            Recruiting intelligence platform
          </p>
        </header>

        <section
          aria-labelledby="status-heading"
          className="mb-10 rounded-lg border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-900"
        >
          <h2
            id="status-heading"
            className="text-sm font-medium text-zinc-900 dark:text-zinc-100"
          >
            Phase 1 — Development foundation
          </h2>
          <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            The full-stack skeleton is in place. No ingestion pipeline, database,
            or recruiter research exists yet.
          </p>
        </section>

        <section aria-labelledby="counters-heading">
          <h2
            id="counters-heading"
            className="text-sm font-medium text-zinc-900 dark:text-zinc-100"
          >
            Pipeline counters
          </h2>
          <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-500">
            No data source connected — these are placeholders, not measurements.
          </p>

          <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {PLACEHOLDER_COUNTERS.map((counter) => (
              <div
                key={counter.key}
                className="rounded-lg border border-dashed border-zinc-300 bg-white p-4 dark:border-zinc-700 dark:bg-zinc-900"
              >
                <dt className="text-xs text-zinc-600 dark:text-zinc-400">
                  {counter.label}
                </dt>
                <dd className="mt-1 text-lg font-medium text-zinc-400 dark:text-zinc-600">
                  &mdash;
                </dd>
              </div>
            ))}
          </dl>
        </section>

        <div className="mt-10">
          <Button disabled>Awaiting Phase 2</Button>
        </div>
      </main>
    </div>
  );
}
