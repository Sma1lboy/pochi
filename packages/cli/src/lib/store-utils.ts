import { getLogger } from "@getpochi/common";
import type { Store } from "@livestore/livestore";
import type { LiveStoreSchema } from "@livestore/livestore";
import { Effect } from "@livestore/utils/effect";

const logger = getLogger("Shutdown");

/**
 * Safely shutdown the store with timeout
 * - Uses Promise.race to handle timeout vs shutdown completion
 * - Exits with code 1 on timeout, code 0 on success
 */
export async function shutdownStoreAndExit(
  store: Store<LiveStoreSchema>,
): Promise<void> {
  const shutdownPromise = Effect.runPromise(store.shutdown());

  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => {
      reject(new Error("Store shutdown timed out"));
    }, 5000);
  });

  try {
    await Promise.race([shutdownPromise, timeoutPromise]);
    logger.debug("Store shutdown completed");
    process.exit(0);
  } catch (error) {
    logger.debug("Store shutdown timed out or failed");
    process.exit(1);
  }
}
