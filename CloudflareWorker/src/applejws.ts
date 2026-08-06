import { SignedDataVerifier, VerificationException, VerificationStatus, Environment } from "@apple/app-store-server-library";
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

interface VerifierPair {
    production: SignedDataVerifier;
    sandbox: SignedDataVerifier;
}

// Keyed by "bundleId:appAppleId" rather than a single module-level singleton so that
// tests can change env.APPSTORE_APP_APPLE_ID between cases and see it take effect —
// in production this key is constant for the life of the isolate, so it's a no-op cost.
const verifierCache = new Map<string, VerifierPair>();

function getVerifiers(bundleId: string, appAppleId: number): VerifierPair {
    const cacheKey = `${bundleId}:${appAppleId}`;
    let pair = verifierCache.get(cacheKey);
    if (!pair) {
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
    const { production, sandbox } = getVerifiers(opts.bundleId, opts.appAppleId);

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

export function healthCheckAppleJws(bundleId: string, rawAppAppleId: string): { ok: boolean; error?: string } {
    const appAppleId = Number.parseInt(rawAppAppleId, 10);
    if (!Number.isInteger(appAppleId) || appAppleId <= 0) {
        return { ok: false, error: "APPSTORE_APP_APPLE_ID is not configured or not a positive integer" };
    }
    try {
        getVerifiers(bundleId, appAppleId);
        return { ok: true };
    } catch (err) {
        return { ok: false, error: String(err) };
    }
}
