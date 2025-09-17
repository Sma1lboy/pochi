import { getLogger } from "@getpochi/common";
import type { Store } from "@livestore/livestore";
import type { LiveStoreSchema } from "@livestore/livestore";
import { Effect } from "@livestore/utils/effect";

const logger = getLogger("Shutdown");

export async function shutdownStoreAndExit(
  store: Store<LiveStoreSchema>,
): Promise<void> {
  try {
    await Promise.race([
      Effect.runPromise(store.shutdown()),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("timeout")), 5000)
      ),
    ]);
    logger.debug("Store shutdown completed");
    process.exit(0);
  } catch (error) {
    if (error instanceof Error && error.message === "timeout") {
      logger.debug("Store shutdown timed out, continuing...");
    } else {
      logger.debug("Store shutdown failed, continuing...");
    }
    process.exit(1);
  }
}
