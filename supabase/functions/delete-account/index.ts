import { handleDevelopmentDeletion } from "../_shared/development-cleanup.ts";
import { handleResearchDeletion } from "../_shared/research-cleanup.ts";

Deno.serve(async (request: Request) => {
  const development = await handleDevelopmentDeletion(request);
  if (!development.ok) return development;
  return handleResearchDeletion(request, true);
});
