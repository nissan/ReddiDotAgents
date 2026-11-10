// Balances subagent spawns across subscription quota lanes: Claude (anthropic), ChatGPT (openai-codex),
// Antigravity Gemini, and Antigravity's Claude pool.
//
// Agents opt in through `task.agentModelOverrides` pointing at a tier role (`@cheap`, `@mid`, `@high`), or a
// spawn names `@frontier` (Claude Fable or GPT Astra, whichever subscription has quota).
// Each tier has one concrete role per lane in `modelRoles` (`<tier>_<lane>`).
// Spawns are distributed by smooth weighted round-robin; a lane's weight is how far it is under its
// quota pace (remaining fraction / time-to-reset fraction, tightest window wins), read from
// `omp usage --json`. The other lanes of the tier follow as the child's retry fallbacks.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type Tier = "cheap" | "mid" | "high" | "frontier";

interface UsageLimit {
	id?: string;
	scope?: { tier?: string };
	window?: { durationMs?: number; resetsAt?: number };
	amount?: { remainingFraction?: number };
}
interface UsageReport {
	provider: string;
	limits?: UsageLimit[];
}

interface Lane {
	/** Role suffix: `modelRoles.<tier>_<name>`. */
	name: string;
	provider: string;
	tiers: readonly Tier[];
	/** Whether a quota window of `provider` gates this lane's model for `tier`. */
	counts(limit: UsageLimit, tier: Tier): boolean;
}

/** The three complexity tiers every full lane serves; `frontier` is listed per lane. */
const ALL_TIERS: readonly Tier[] = ["cheap", "mid", "high"];
const WITH_FRONTIER: readonly Tier[] = [...ALL_TIERS, "frontier"];
const TIERS: Record<string, Tier> = { cheap: "cheap", mid: "mid", high: "high", frontier: "frontier" };

const LANES: readonly Lane[] = [
	// Model-tier windows (e.g. Fable-only) do not gate Haiku/Sonnet/Opus; they do gate the frontier tier.
	{
		name: "claude",
		provider: "anthropic",
		tiers: WITH_FRONTIER,
		counts: (l, tier) => tier === "frontier" || !l.scope?.tier,
	},
	{ name: "gpt", provider: "openai-codex", tiers: WITH_FRONTIER, counts: () => true },
	// Gemini windows; the Argon-only window gates just the `high` tier's gemini-4-argon.
	{
		name: "gemini",
		provider: "google-antigravity",
		tiers: ALL_TIERS,
		counts: (l, tier) => !!l.id?.includes(":google:") && (tier === "high" || !l.id.includes("argon")),
	},
	// Antigravity's "Claude & GPT (shared)" pool; it has no Haiku, so no cheap tier.
	{
		name: "agclaude",
		provider: "google-antigravity",
		tiers: ["mid", "high"],
		counts: l => !!l.id?.includes(":anthropic:"),
	},
];

const USAGE_TTL_MS = 180_000;
const USAGE_TIMEOUT_MS = 8_000;
const FIRST_FETCH_WAIT_MS = 4_000;
/** Below this remaining fraction a window counts as exhausted. */
const MIN_REMAINING = 0.05;
/** Caps how strongly a soon-to-reset window is preferred. */
const MAX_PACE = 4;
/** Floor for time-to-reset so a window about to reset does not divide by ~0. */
const MIN_TIME_LEFT = 0.05;

/** Undefined until the first successful fetch: every lane then weighs 1. */
let reports: UsageReport[] | undefined;
let fetchedAt = 0;
let inflight: Promise<void> | undefined;
let lastError: string | undefined;
const swrrCurrent: Record<Tier, Record<string, number>> = { cheap: {}, mid: {}, high: {}, frontier: {} };

function paceScore(limit: UsageLimit, now: number): number {
	const remaining = limit.amount?.remainingFraction;
	if (typeof remaining !== "number") return MAX_PACE;
	if (remaining < MIN_REMAINING) return 0;
	const duration = limit.window?.durationMs;
	const resetsAt = limit.window?.resetsAt;
	const timeLeft =
		duration && resetsAt ? Math.min(1, Math.max(MIN_TIME_LEFT, (resetsAt - now) / duration)) : 1;
	return Math.min(MAX_PACE, remaining / timeLeft);
}

function laneWeight(lane: Lane, tier: Tier, now: number): number {
	if (!reports) return 1;
	let weight = 0;
	// Accounts of one provider add capacity; one account is bound by its tightest window.
	for (const report of reports) {
		if (report.provider !== lane.provider) continue;
		const scores = (report.limits ?? []).filter(l => lane.counts(l, tier)).map(l => paceScore(l, now));
		weight += scores.length ? Math.min(...scores) : MAX_PACE;
	}
	return weight;
}

function parseReports(raw: unknown): UsageReport[] {
	if (!raw || typeof raw !== "object" || !("reports" in raw) || !Array.isArray(raw.reports)) {
		throw new Error("omp usage --json: missing reports[]");
	}
	// Limit fields are read defensively in paceScore/counts; only the provider id is required here.
	const parsed: UsageReport[] = raw.reports.filter(
		(r: unknown) => !!r && typeof r === "object" && "provider" in r && typeof r.provider === "string",
	);
	return parsed;
}

async function fetchUsage(): Promise<void> {
	try {
		const omp = Bun.which("omp") ?? process.execPath;
		const proc = Bun.spawn([omp, "usage", "--json", "--no-extensions"], {
			stdout: "pipe",
			stderr: "ignore",
			timeout: USAGE_TIMEOUT_MS,
		});
		const [stdout, code] = await Promise.all([new Response(proc.stdout).text(), proc.exited]);
		if (code !== 0) throw new Error(`omp usage exited with ${code}`);
		reports = parseReports(JSON.parse(stdout));
		lastError = undefined;
	} catch (e) {
		// Keep the previous reports; the note on the next spawn surfaces the failure.
		lastError = e instanceof Error ? e.message.split("\n")[0] : String(e);
	} finally {
		fetchedAt = Date.now();
	}
}

function refreshUsage(): Promise<void> {
	inflight ??= fetchUsage().finally(() => {
		inflight = undefined;
	});
	return inflight;
}

/**
 * Smooth weighted round-robin (nginx) over the tier's lanes: proportional and evenly interleaved.
 * Returns lanes in attempt order: the pick, then the rest by descending weight.
 */
function orderLanes(tier: Tier): { lane: Lane; weight: number }[] {
	const now = Date.now();
	let entries = LANES.filter(l => l.tiers.includes(tier)).map(lane => ({ lane, weight: laneWeight(lane, tier, now) }));
	// Every lane exhausted: rotate evenly and let provider errors drive the fallback chain.
	if (entries.every(e => e.weight === 0)) entries = entries.map(e => ({ ...e, weight: 1 }));
	const current = swrrCurrent[tier];
	const total = entries.reduce((sum, e) => sum + e.weight, 0);
	let best = entries[0];
	for (const e of entries) {
		current[e.lane.name] = (current[e.lane.name] ?? 0) + e.weight;
		if (current[e.lane.name] > current[best.lane.name]) best = e;
	}
	current[best.lane.name] -= total;
	const rest = entries.filter(e => e !== best).sort((a, b) => b.weight - a.weight);
	return [best, ...rest];
}

function tierOf(modelRole: string | undefined): Tier | undefined {
	const role = modelRole?.replace(/^@/, "").split(":")[0];
	return role ? TIERS[role] : undefined;
}

export default function providerBalancer(pi: ExtensionAPI) {
	pi.setLabel("Provider balancer");

	pi.on("session_start", () => {
		if (!fetchedAt) void refreshUsage();
	});

	pi.on("before_subagent_spawn", async event => {
		const tier = tierOf(event.modelRole);
		if (!tier) return;

		if (!fetchedAt) {
			await Promise.race([refreshUsage(), Bun.sleep(FIRST_FETCH_WAIT_MS)]);
		} else if (Date.now() - fetchedAt > USAGE_TTL_MS) {
			void refreshUsage();
		}

		const order = orderLanes(tier);
		const weights = order.map(e => `${e.lane.name}=${e.weight.toFixed(2)}`).join(" ");
		return {
			model: order.map(e => `@${tier}_${e.lane.name}`),
			note: `${tier} → ${order[0].lane.name} (${weights}${lastError ? `; usage stale: ${lastError}` : ""})`,
		};
	});
}
