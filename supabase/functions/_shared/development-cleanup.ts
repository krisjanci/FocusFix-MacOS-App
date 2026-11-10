// Server-only credentials. A signed-in user can delete only their own uploads.
export async function handleDevelopmentDeletion(request: Request): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const origin = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const adminKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!origin || !publicKey || !adminKey) return new Response(null, { status: 503 });
  if (!authorization?.startsWith("Bearer ")) return new Response(null, { status: 401 });
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  try {
    const userHeaders = { apikey: publicKey, Authorization: authorization, "Content-Type": "application/json" };
    const userResponse = await fetch(`${origin}/auth/v1/user`, { headers: userHeaders });
    if (!userResponse.ok) return new Response(null, { status: 401 });
    const user = await userResponse.json();
    if (typeof user.id !== "string" || !uuid.test(user.id)) return new Response(null, { status: 401 });
    const owner = user.id.toLowerCase();
    // The RPC revokes consent before any storage operation and records unfinished cleanup.
    const recorded = await fetch(`${origin}/rest/v1/rpc/request_development_deletion`, {
      method: "POST", headers: userHeaders, body: "{}",
    });
    if (!recorded.ok) throw new Error("Could not record deletion request");
    const requestID = await recorded.json();
    if (typeof requestID !== "string" || !uuid.test(requestID)) throw new Error("Invalid request ID");

    const headers = { apikey: adminKey, Authorization: `Bearer ${adminKey}`, "Content-Type": "application/json" };
    const admin = async (path: string, method: string, body?: unknown) => {
      const response = await fetch(`${origin}/${path}`, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (!response.ok) throw new Error("Storage cleanup failed");
      return response;
    };
    const paths: string[] = [];
    async function list(prefix: string, depth: number): Promise<void> {
      if (depth > 3) throw new Error("Unexpected storage layout");
      for (let offset = 0; ; offset += 100) {
        const response = await admin("storage/v1/object/list/development-recordings", "POST",
          { prefix, limit: 100, offset, sortBy: { column: "name", order: "asc" } });
        const entries = await response.json();
        if (!Array.isArray(entries)) throw new Error("Invalid storage response");
        for (const entry of entries) {
          if (typeof entry.name !== "string" || !entry.name || entry.name === "." || entry.name === ".." || entry.name.includes("/")) {
            throw new Error("Invalid object name");
          }
          const path = `${prefix}/${entry.name}`;
          if (entry.id) paths.push(path); else await list(path, depth + 1);
          if (paths.length > 10000) throw new Error("Manual storage cleanup required");
        }
        if (entries.length < 100) break;
      }
    }
    await list(owner, 0);
    for (let i = 0; i < paths.length; i += 100) {
      await admin("storage/v1/object/development-recordings", "DELETE", { prefixes: paths.slice(i, i + 100) });
    }
    // A downloaded copy needs separate owner review; do not falsely mark it deleted.
    await admin(`rest/v1/development_deletion_requests?id=eq.${requestID}&owner_reference=eq.${owner}&status=eq.pending`,
      "PATCH", { status: "hosted_deleted" });
    return Response.json({ request_id: requestID, status: "hosted_deleted" });
  } catch {
    // Never return credentials, emails, server responses, or recording contents.
    return new Response(null, { status: 503 });
  }
}
