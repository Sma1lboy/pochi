import type { Store } from "@livestore/livestore";
import { getLogger } from "@getpochi/common";
import type { OutputRenderer } from "./output-renderer";
import type { LiveStoreSchema } from "@livestore/livestore";

const logger = getLogger("Shutdown");

let isShuttingDown = false;
const shutdownCallbacks: Array<() => Promise<void>> = [];

export function setupShutdownHandlers(): void {
  process.once("SIGINT", () => handleShutdown("SIGINT"));
  process.once("SIGTERM", () => handleShutdown("SIGTERM"));

  process.on("uncaughtException", (error) => {
    logger.error("Uncaught exception:", error);
    handleShutdown("uncaughtException");
  });

  process.on("unhandledRejection", (reason, promise) => {
    logger.error("Unhandled rejection at:", promise, "reason:", reason);
    handleShutdown("unhandledRejection");
  });
}

export function registerShutdownCallback(callback: () => Promise<void>): void {
  shutdownCallbacks.push(callback);
}

async function handleShutdown(reason: string): Promise<void> {
  if (isShuttingDown) {
    logger.debug("Shutdown already in progress");
    return;
  }
  isShuttingDown = true;
  logger.debug(`Received ${reason}, initiating graceful shutdown...`);

  // Force exit after 7 seconds if graceful shutdown fails
  const forceExitTimer = setTimeout(() => {
    logger.warn(`Force exiting after 7 seconds due to ${reason}`);
    process.exit(reason === "SIGINT" ? 130 : 1);
  }, 7000);

  try {
    // Run all shutdown callbacks with a 6 second timeout
    await Promise.race([
      Promise.allSettled(
        shutdownCallbacks.map(async (callback) => {
          try {
            await callback();
          } catch (error) {
            logger.error("Error in shutdown callback:", error);
          }
        }),
      ),
      new Promise<void>((resolve) => {
        setTimeout(() => {
          logger.warn("Graceful shutdown timed out after 6 seconds");
          resolve();
        }, 6000);
      }),
    ]);

    logger.debug("Graceful shutdown completed");
    clearTimeout(forceExitTimer);
    process.exit(reason === "SIGINT" ? 130 : 0);
  } catch (error) {
    logger.error("Fatal error during shutdown:", error);
    clearTimeout(forceExitTimer);
    process.exit(1);
  }
}

/**
 * Wrapper for store.shutdown() that ensures it won't hang
 * - Waits max 5 seconds for shutdown
 * - Catches and ignores any errors
 * - Always resolves (never rejects or hangs)
 */
export async function safeStoreShutdown(
  store: Store<LiveStoreSchema>,
): Promise<void> {
  try {
    logger.debug("Shutting down store...");

    let timeoutId: NodeJS.Timeout | null = null;
    let didTimeout = false;

    // Create a timeout promise that resolves after 5 seconds
    const timeoutPromise = new Promise<void>((resolve) => {
      timeoutId = setTimeout(() => {
        didTimeout = true;
        logger.warn("Store shutdown timed out after 5 seconds, continuing...");
        resolve();
      }, 5000);
    });

    // Try to shutdown the store, but don't wait more than 5 seconds
    await Promise.race([
      // Wrap store.shutdown() to handle both Promise and Effect types
      Promise.resolve(store.shutdown())
        .then(() => {
          // Clear the timeout if store shutdown succeeds
          if (timeoutId) {
            clearTimeout(timeoutId);
          }
          if (!didTimeout) {
            logger.debug("Store shutdown completed successfully");
          }
        })
        .catch((error: unknown) => {
          // Clear the timeout if store shutdown fails
          if (timeoutId) {
            clearTimeout(timeoutId);
          }
          logger.error("Error during store shutdown:", error);
          // Ignore error and continue
        }),
      timeoutPromise,
    ]);
  } catch (error) {
    // This should rarely happen, but ensure we never throw
    logger.error("Unexpected error in safeStoreShutdown:", error);
  }
}

/**
 * Safe wrapper for renderer shutdown
 * - Catches and logs any errors
 * - Never throws
 */
export function safeRendererShutdown(renderer: OutputRenderer): void {
  try {
    renderer.shutdown();
  } catch (error) {
    logger.error("Error during renderer shutdown:", error);
  }
}
