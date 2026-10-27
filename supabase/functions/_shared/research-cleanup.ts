// Server-only credentials. The request body never selects whose data is deleted.
export async function handleResearchDeletion(request: Request, deleteAccount: boolean): Promise<Response> {
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
    // This transaction revokes uploads first and retains a request for researcher-held copies,
    // even if cloud cleanup fails or the account is subsequently deleted.
    const recorded = await fetch(`${origin}/rest/v1/rpc/request_research_deletion`, {
      method: "POST", headers: userHeaders, body: "{}",
    });
    if (!recorded.ok) throw new Error("Could not record deletion request");
    const requestID = await recorded.json();
    if (typeof requestID !== "string" || !uuid.test(requestID)) throw new Error("Invalid request ID");
    const headers = { apikey: adminKey, Authorization: `Bearer ${adminKey}`, "Content-Type": "application/json" };
    const admin = async (path: string, method: string, body?: unknown) => {
      const result = await fetch(`${origin}/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
      if (!result.ok) throw new Error("Admin operation failed");
      return result;
    };
    const paths: string[] = [];
    async function list(prefix: string, depth: number): Promise<void> {
      if (depth > 3) throw new Error("Unexpected storage layout");
      for (let offset = 0; ; offset += 100) {
        const response = await admin("storage/v1/object/list/research-sessions", "POST",
          { prefix, limit: 100, offset, sortBy: { column: "name", order: "asc" } });
        const items = await response.json();
        if (!Array.isArray(items)) throw new Error("Invalid list response");
        for (const item of items) {
          if (typeof item.name !== "string" || item.name.includes("/") || item.name === ".." || item.name === "." || item.name === "") throw new Error("Invalid object name");
          const path = `${prefix}/${item.name}`;
          if (item.id) paths.push(path); else await list(path, depth + 1);
          if (paths.length > 10000) throw new Error("Manual storage cleanup required");
        }
        if (items.length < 100) break;
      }
    }
    await list(owner, 0);
    for (let i = 0; i < paths.length; i += 100) {
      await admin("storage/v1/object/research-sessions", "DELETE", { prefixes: paths.slice(i, i + 100) });
    }
    // This is deliberately not "completed": downloaded copies require researcher review.
    await admin(`rest/v1/research_deletion_requests?id=eq.${requestID}&participant_reference=eq.${owner}&status=eq.pending`,
      "PATCH", { status: "hosted_deleted" });
    if (deleteAccount) await admin(`auth/v1/admin/users/${owner}`, "DELETE", { should_soft_delete: false });
    return Response.json({ request_id: requestID, status: "hosted_deleted" });
  } catch {
    // Never echo tokens, server bodies, emails or recording data.
    return new Response(null, { status: 503 });
  }
}
