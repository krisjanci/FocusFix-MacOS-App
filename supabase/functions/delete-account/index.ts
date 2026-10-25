// Deploy server-side only. SUPABASE_SERVICE_ROLE_KEY must NEVER be placed in the app.
// No third-party dependencies; verify the caller with Auth before using admin APIs.
Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const origin = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const adminKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!origin || !publicKey || !adminKey) return new Response(null, { status: 503 });
  if (!authorization?.startsWith("Bearer ")) return new Response(null, { status: 401 });
  try {
    const userResponse = await fetch(`${origin}/auth/v1/user`, {
      headers: { apikey: publicKey, Authorization: authorization },
    });
    if (!userResponse.ok) return new Response(null, { status: 401 });
    const user = await userResponse.json();
    if (typeof user.id !== "string" || !/^[0-9a-f-]{36}$/i.test(user.id)) return new Response(null, { status: 401 });
    const owner = user.id.toLowerCase();
    const headers = { apikey: adminKey, Authorization: `Bearer ${adminKey}`, "Content-Type": "application/json" };
    const admin = async (path: string, method: string, body?: unknown) => {
      const result = await fetch(`${origin}/${path}`, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      });
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
          if (typeof item.name !== "string" || item.name.includes("/") || item.name === "..") throw new Error("Invalid object name");
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
    await admin(`auth/v1/admin/users/${owner}`, "DELETE", { should_soft_delete: false });
    return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
  } catch {
    // No tokens, emails, server bodies or recording data in logs or errors.
    return new Response(null, { status: 503 });
  }
});
