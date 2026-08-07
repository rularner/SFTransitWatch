import { APPLE_ROOT_CA_G3_DER_BASE64 } from "./appleRootCertificate";

export const WORKER_PROXY_PRODUCT_IDS = ["org.larner.SFTransitWatch.proxy.monthly"];

export interface VerifiedTransaction {
    originalTransactionId: string;
    transactionId: string;
    bundleId: string;
    productId: string;
    environment: "Sandbox" | "Production";
    expiresDateMs: number;
}

export type VerifyResult = { ok: true; payload: VerifiedTransaction } | { ok: false; reason: string };

// @apple/app-store-server-library pulls in jsrsasign, which seeds an internal PRNG pool
// via crypto.getRandomValues() as a side effect of merely loading the module — not of
// calling any of its functions. Workers forbids randomness/async I/O outside of
// request-handling context ("global scope"), so a static top-level import here crashes
// the Worker at startup, before it ever serves a request (confirmed via `wrangler dev`,
// which runs the real workerd engine locally: "Disallowed operation called within global
// scope"). A dynamic import, first triggered from inside a request handler and never at
// module load time, defers that side effect into request context, where it's allowed.
type AppleLib = typeof import("@apple/app-store-server-library");
let applePromise: Promise<AppleLib> | undefined;
function loadAppleLib(): Promise<AppleLib> {
    if (!applePromise) applePromise = import("@apple/app-store-server-library");
    return applePromise;
}

interface VerifierPair {
    production: InstanceType<AppleLib["SignedDataVerifier"]>;
    sandbox: InstanceType<AppleLib["SignedDataVerifier"]>;
}

// Keyed by "bundleId:appAppleId" rather than a single module-level singleton so that
// tests can change env.APPSTORE_APP_APPLE_ID between cases and see it take effect —
// in production this key is constant for the life of the isolate, so it's a no-op cost.
const verifierCache = new Map<string, VerifierPair>();

async function getVerifiers(bundleId: string, appAppleId: number): Promise<VerifierPair> {
    const cacheKey = `${bundleId}:${appAppleId}`;
    let pair = verifierCache.get(cacheKey);
    if (!pair) {
        const { SignedDataVerifier, Environment } = await loadAppleLib();
        const root = [Buffer.from(APPLE_ROOT_CA_G3_DER_BASE64, "base64")];
        pair = {
            production: new SignedDataVerifier(root, false, Environment.PRODUCTION, bundleId, appAppleId),
            sandbox: new SignedDataVerifier(root, false, Environment.SANDBOX, bundleId),
        };
        verifierCache.set(cacheKey, pair);
    }
    return pair;
}

export async function verifyAppleTransactionJWS(
    jws: string,
    opts: { bundleId: string; appAppleId: number; productIds: string[] },
): Promise<VerifyResult> {
    let production: VerifierPair["production"], sandbox: VerifierPair["sandbox"];
    try {
        ({ production, sandbox } = await getVerifiers(opts.bundleId, opts.appAppleId));
    } catch (err) {
        return { ok: false, reason: `verifier construction failed: ${String(err)}` };
    }

    const { VerificationException, VerificationStatus } = await loadAppleLib();

    let decoded;
    try {
        decoded = await production.verifyAndDecodeTransaction(jws);
    } catch (err) {
        if (err instanceof VerificationException && err.status === VerificationStatus.INVALID_ENVIRONMENT) {
            try {
                decoded = await sandbox.verifyAndDecodeTransaction(jws);
            } catch (sandboxErr) {
                return { ok: false, reason: `sandbox verification failed: ${String(sandboxErr)}` };
            }
        } else {
            return { ok: false, reason: `production verification failed: ${String(err)}` };
        }
    }

    const { originalTransactionId, transactionId, bundleId, productId, environment, expiresDate } = decoded;
    if (typeof originalTransactionId !== "string" || !/^[0-9]+$/.test(originalTransactionId)) {
        return { ok: false, reason: "originalTransactionId missing or not numeric" };
    }
    if (typeof transactionId !== "string") {
        return { ok: false, reason: "transactionId missing" };
    }
    if (typeof productId !== "string" || !opts.productIds.includes(productId)) {
        return { ok: false, reason: "productId not recognized" };
    }
    if (typeof expiresDate !== "number") {
        return { ok: false, reason: "expiresDate missing" };
    }
    if (environment !== "Sandbox" && environment !== "Production") {
        return { ok: false, reason: "environment missing or unrecognized" };
    }

    return {
        ok: true,
        payload: {
            originalTransactionId,
            transactionId,
            bundleId: bundleId ?? opts.bundleId,
            productId,
            environment,
            expiresDateMs: expiresDate,
        },
    };
}

export async function healthCheckAppleJws(bundleId: string, rawAppAppleId: string): Promise<{ ok: boolean; error?: string }> {
    const appAppleId = Number.parseInt(rawAppAppleId, 10);
    if (!Number.isInteger(appAppleId) || appAppleId <= 0) {
        return { ok: false, error: "APPSTORE_APP_APPLE_ID is not configured or not a positive integer" };
    }
    try {
        await getVerifiers(bundleId, appAppleId);
        return { ok: true };
    } catch (err) {
        return { ok: false, error: String(err) };
    }
}
