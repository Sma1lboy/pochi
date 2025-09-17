import { getLogger } from "@getpochi/common";
import type { Store } from "@livestore/livestore";
import type { LiveStoreSchema } from "@livestore/livestore";
import { Effect } from "@livestore/utils/effect";

const logger = getLogger("Shutdown");

/**
 * Safely shutdown the store with timeout
 * - Uses Promise.race to handle timeout vs shutdown completion
 * - Returns true if shutdown completed successfully, false if timed out or failed
 */
export async function safeShutdownStore(
  store: Store<LiveStoreSchema>,
): Promise<boolean> {
  const shutdownPromise = Effect.runPromise(store.shutdown()).then(
    () => true,
    (error) => {
      logger.debug("Store shutdown failed:", error);
      return false;
    },
  );

  const timeoutPromise = new Promise<false>((resolve) => {
    setTimeout(() => {
      logger.debug("Store shutdown timed out");
      resolve(false);
    }, 5000);
  });

  const success = await Promise.race([shutdownPromise, timeoutPromise]);

  if (success) {
    logger.debug("Store shutdown completed");
  }

  return success;
}

/**
 * Shutdown store and exit process with appropriate code
 */
export async function shutdownStoreAndExit(
  store: Store<LiveStoreSchema>,
): Promise<void> {
  const success = await safeShutdownStore(store);
  process.exit(success ? 0 : 1);
}
