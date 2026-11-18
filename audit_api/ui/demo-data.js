/** Synthetic audit data for UI preview (no live API required). */
window.AUDIT_DEMO = (() => {
  const hoursAgo = (h, m = 0) => {
    const d = new Date(Date.now() - h * 3600e3 - m * 60e3);
    return d.toISOString();
  };

  const events = [
    {
      id: "demo-e01",
      time: hoursAgo(0, 12),
      who: "demo-reader.agents.internal",
      action: "read",
      category: "prompt.read",
      target: "secret/data/prompts/tch/demo/nursing_assistant_agent",
      space: "demo",
      agent: "nursing_assistant_agent",
      result: "allowed",
      request_id: "req-demo-01",
    },
    {
      id: "demo-e02",
      time: hoursAgo(0, 18),
      who: "demo-reader.agents.internal",
      action: "update",
      category: "auth.cert.login",
      target: "auth/cert/login",
      space: "demo",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-02",
    },
    {
      id: "demo-e03",
      time: hoursAgo(1, 5),
      who: "gitops-pipeline",
      action: "update",
      category: "prompt.write",
      target: "secret/data/prompts/tch/demo/safeguard_agent",
      space: "demo",
      agent: "safeguard_agent",
      result: "allowed",
      request_id: "req-demo-03",
    },
    {
      id: "demo-e04",
      time: hoursAgo(1, 6),
      who: "gitops-pipeline",
      action: "update",
      category: "prompt.write",
      target: "secret/data/prompts/tch/demo/output_judge_agent",
      space: "demo",
      agent: "output_judge_agent",
      result: "allowed",
      request_id: "req-demo-04",
    },
    {
      id: "demo-e05",
      time: hoursAgo(1, 7),
      who: "gitops-pipeline",
      action: "update",
      category: "cert.write",
      target: "secret/data/agent-certs/tch/demo",
      space: "demo",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-05",
    },
    {
      id: "demo-e06",
      time: hoursAgo(2, 20),
      who: "vault-admin@hospital-a",
      action: "update",
      category: "prompt.metadata",
      target: "secret/metadata/prompts/tch/racc/claims_agent",
      space: "racc",
      agent: "claims_agent",
      result: "allowed",
      request_id: "req-demo-06",
    },
    {
      id: "demo-e07",
      time: hoursAgo(3, 2),
      who: "racc-reader.agents.internal",
      action: "read",
      category: "prompt.read",
      target: "secret/data/prompts/tch/racc/claims_agent",
      space: "racc",
      agent: "claims_agent",
      result: "allowed",
      request_id: "req-demo-07",
    },
    {
      id: "demo-e08",
      time: hoursAgo(3, 40),
      who: "demo-reader.agents.internal",
      action: "read",
      category: "policy.denied",
      target: "secret/data/prompts/tch/racc/claims_agent",
      space: "racc",
      agent: "claims_agent",
      result: "denied",
      error: "1 error occurred:\n\t* permission denied\n",
      request_id: "req-demo-08",
    },
    {
      id: "demo-e09",
      time: hoursAgo(5, 10),
      who: "approle",
      action: "read",
      category: "cert.read",
      target: "secret/data/agent-certs/tch/shared",
      space: "shared",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-09",
    },
    {
      id: "demo-e10",
      time: hoursAgo(6, 0),
      who: "jwt-github-repo:XelerAIT-Solutions/tch:ref:refs/heads/prompt-vault",
      action: "update",
      category: "auth.jwt.login",
      target: "auth/jwt-github/login",
      space: "—",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-10",
    },
    {
      id: "demo-e11",
      time: hoursAgo(8, 15),
      who: "userpass-admin",
      action: "delete",
      category: "prompt.delete",
      target: "secret/data/prompts/tch/demo/retired_agent",
      space: "demo",
      agent: "retired_agent",
      result: "allowed",
      request_id: "req-demo-11",
    },
    {
      id: "demo-e12",
      time: hoursAgo(9, 30),
      who: "unknown",
      action: "read",
      category: "other",
      target: "auth/token/lookup-self",
      space: "—",
      agent: "—",
      result: "denied",
      error: "permission denied",
      request_id: "req-demo-12",
    },
    {
      id: "demo-e13",
      time: hoursAgo(12, 0),
      who: "pod-reader.agents.internal",
      action: "list",
      category: "prompt.list",
      target: "secret/metadata/prompts/tch/pod/",
      space: "pod",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-13",
    },
    {
      id: "demo-e14",
      time: hoursAgo(14, 45),
      who: "approle",
      action: "update",
      category: "cert.write",
      target: "secret/data/agent-certs/tch/demo",
      space: "demo",
      agent: "—",
      result: "allowed",
      request_id: "req-demo-14",
    },
    {
      id: "demo-e15",
      time: hoursAgo(18, 5),
      who: "bad-cert.agents.internal",
      action: "update",
      category: "auth.cert.login",
      target: "auth/cert/login",
      space: "—",
      agent: "—",
      result: "denied",
      error: "invalid client certificate",
      request_id: "req-demo-15",
    },
  ];

  const publishes = [
    {
      run_id: "pub-2026-11-18-a1",
      started_at: hoursAgo(1, 8),
      ended_at: hoursAgo(1, 5),
      actor: "gitops-pipeline",
      agents: ["safeguard_agent", "output_judge_agent"],
      event_count: 3,
      events: [events[2], events[3], events[4]],
    },
    {
      run_id: "pub-2026-11-17-b2",
      started_at: hoursAgo(26, 0),
      ended_at: hoursAgo(25, 50),
      actor: "gitops-pipeline",
      agents: ["nursing_assistant_agent"],
      event_count: 2,
      events: [],
    },
  ];

  const byCategory = (pred) => events.filter(pred);

  return {
    summary: {
      totals: { events: 248, allowed: 211, denied: 37 },
      by_action: { read: 120, update: 88, list: 30, create: 6, delete: 4 },
    },
    activity: { items: events },
    publishes: { items: publishes },
    publishDetail: Object.fromEntries(publishes.map((p) => [p.run_id, { run: p }])),
    eventsById: Object.fromEntries(events.map((e) => [e.id, { event: e }])),
    certs: {
      items: byCategory((e) => e.category === "cert.read" || e.category === "cert.write"),
    },
    agents: {
      items: byCategory(
        (e) =>
          e.category === "prompt.read" ||
          e.category === "prompt.list" ||
          e.category === "auth.cert.login"
      ),
    },
    admin: {
      items: byCategory(
        (e) =>
          e.category === "prompt.metadata" ||
          e.category === "prompt.delete" ||
          e.category === "auth.jwt.login"
      ),
    },
    failures: {
      items: byCategory((e) => e.result === "denied"),
    },
  };
})();
