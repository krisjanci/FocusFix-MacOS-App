import { handleResearchDeletion } from "../_shared/research-cleanup.ts";
Deno.serve((request: Request) => handleResearchDeletion(request, false));
