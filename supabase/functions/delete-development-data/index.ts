import { handleDevelopmentDeletion } from "../_shared/development-cleanup.ts";

Deno.serve(handleDevelopmentDeletion);
