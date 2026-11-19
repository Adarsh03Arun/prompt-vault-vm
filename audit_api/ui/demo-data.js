/** Synthetic vault activity for the Activity log tab (OpenBao-style display names). */
window.AUDIT_ACTIVITY_DEMO = (() => {
  const hoursAgo = (h, m = 0) =>
    new Date(Date.now() - h * 3600e3 - m * 60e3).toISOString();

  const events = [
    {
      id: "act-01",
      time: hoursAgo(0, 20),
      who: "care-floor-reader.agents.internal",
      action: "read",
      category: "prompt.read",
      target: "secret/data/prompts/tch/care-floor/bedside_triage_assistant",
      space: "care-floor",
      agent: "bedside_triage_assistant",
      result: "allowed",
      request_id: "req-a1",
    },
    {
      id: "act-02",
      time: hoursAgo(1, 0),
      who: "gitops-pipeline",
      action: "update",
      category: "prompt.write",
      target: "secret/data/prompts/tch/care-floor/bedside_triage_assistant",
      space: "care-floor",
      agent: "bedside_triage_assistant",
      result: "allowed",
      request_id: "req-a2",
    },
    {
      id: "act-03",
      time: hoursAgo(1, 2),
      who: "release.manager@xelerait.com",
      action: "update",
      category: "prompt.metadata",
      target: "secret/metadata/prompts/tch/care-floor/bedside_triage_assistant",
      space: "care-floor",
      agent: "bedside_triage_assistant",
      result: "allowed",
      request_id: "req-a3",
    },
    {
      id: "act-04",
      time: hoursAgo(2, 0),
      who: "approle",
      action: "update",
      category: "cert.write",
      target: "secret/data/agent-certs/tch/care-floor",
      space: "care-floor",
      agent: "—",
      result: "allowed",
      request_id: "req-a4",
    },
    {
      id: "act-05",
      time: hoursAgo(3, 10),
      who: "claims-reader.agents.internal",
      action: "read",
      category: "policy.denied",
      target: "secret/data/prompts/tch/care-floor/bedside_triage_assistant",
      space: "care-floor",
      agent: "bedside_triage_assistant",
      result: "denied",
      error: "permission denied",
      request_id: "req-a5",
    },
    {
      id: "act-06",
      time: hoursAgo(4, 0),
      who: "jwt-github-repo:XelerAIT-Solutions/tch:ref:refs/heads/prompt-vault",
      action: "update",
      category: "auth.jwt.login",
      target: "auth/jwt-github/login",
      space: "—",
      agent: "—",
      result: "allowed",
      request_id: "req-a6",
    },
    {
      id: "act-07",
      time: hoursAgo(5, 0),
      who: "vault.admin@xelerait.com",
      action: "delete",
      category: "prompt.delete",
      target: "secret/data/prompts/tch/care-floor/legacy_scribe",
      space: "care-floor",
      agent: "legacy_scribe",
      result: "allowed",
      request_id: "req-a7",
    },
    {
      id: "act-08",
      time: hoursAgo(6, 0),
      who: "unknown",
      action: "read",
      category: "other",
      target: "auth/token/lookup-self",
      space: "—",
      agent: "—",
      result: "denied",
      error: "permission denied",
      request_id: "req-a8",
    },
    {
      id: "act-09",
      time: hoursAgo(8, 0),
      who: "space.owner@hospital.example",
      action: "update",
      category: "prompt.metadata",
      target: "secret/metadata/prompts/tch/claims/insurance_claims_helper",
      space: "claims",
      agent: "insurance_claims_helper",
      result: "allowed",
      request_id: "req-a9",
    },
    {
      id: "act-10",
      time: hoursAgo(12, 0),
      who: "approle",
      action: "read",
      category: "cert.read",
      target: "secret/data/agent-certs/tch/shared",
      space: "shared",
      agent: "—",
      result: "allowed",
      request_id: "req-a10",
    },
  ];

  const publishes = [
    {
      run_id: "pub-2026-11-19-a",
      started_at: hoursAgo(1, 5),
      ended_at: hoursAgo(1, 0),
      actor: "gitops-pipeline",
      agents: ["bedside_triage_assistant", "discharge_summary_assistant"],
      event_count: 4,
    },
  ];

  return {
    summary: { totals: { events: 1519, allowed: 1195, denied: 324 } },
    activity: { items: events },
    publishes: { items: publishes },
    publishDetail: Object.fromEntries(publishes.map((p) => [p.run_id, { run: p }])),
    eventsById: Object.fromEntries(events.map((e) => [e.id, { event: e }])),
    certs: { items: events.filter((e) => String(e.category).startsWith("cert.")) },
    agents: {
      items: events.filter((e) => e.category === "prompt.read" || e.category === "auth.cert.login"),
    },
    admin: {
      items: events.filter(
        (e) =>
          e.category === "prompt.metadata" ||
          e.category === "auth.jwt.login" ||
          e.category === "prompt.delete" ||
          String(e.who).includes("@")
      ),
    },
    failures: { items: events.filter((e) => e.result === "denied") },
  };
})();
