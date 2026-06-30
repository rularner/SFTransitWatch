const ACTIVE_STATUSES = new Set([1, 4]); // 1 = active, 4 = billing grace period

export interface AppStoreEnv {
	APPSTORE_KEY_ID: string;
	APPSTORE_ISSUER_ID: string;
	APPSTORE_PRIVATE_KEY: string;
	APPSTORE_BUNDLE_ID: string;
}

export type SubscriptionStatus = { active: true; expiresAtMs: number } | { active: false };

interface AppStoreSubscriptionResponse {
	data?: Array<{
		lastTransactions?: Array<{ status: number; signedTransactionInfo: string }>;
	}>;
}

export async function verifySubscription(
	env: AppStoreEnv,
	originalTransactionId: string,
): Promise<SubscriptionStatus> {
	const jwt = await signAppStoreJWT(env);

	const prodResp = await fetchSubscriptionStatus("api.storekit.itunes.apple.com", originalTransactionId, jwt);
	let resp = prodResp;
	let usedSandbox = false;
	if (prodResp.status === 404) {
		resp = await fetchSubscriptionStatus("api.storekit-sandbox.itunes.apple.com", originalTransactionId, jwt);
		usedSandbox = true;
	}
	if (!resp.ok) {
		const body = await resp.text().catch(() => "");
		console.warn(JSON.stringify({ source: "verify-sub", reason: "http_not_ok", prodStatus: prodResp.status, usedSandbox, finalStatus: resp.status, body: body.slice(0, 300) }));
		return { active: false };
	}

	const data = (await resp.json()) as AppStoreSubscriptionResponse;
	const last = data.data?.[0]?.lastTransactions?.[0];
	if (!last) {
		console.warn(JSON.stringify({ source: "verify-sub", reason: "no_last_transaction", usedSandbox, dataCount: data.data?.length ?? 0 }));
		return { active: false };
	}

	const payload = decodeJwsPayload(last.signedTransactionInfo);
	const expiresAtMs = typeof payload.expiresDate === "number" ? payload.expiresDate : 0;

	if (ACTIVE_STATUSES.has(last.status) && expiresAtMs > Date.now()) {
		return { active: true, expiresAtMs };
	}
	console.warn(JSON.stringify({ source: "verify-sub", reason: "inactive", usedSandbox, txStatus: last.status, expiresAtMs, now: Date.now() }));
	return { active: false };
}

export async function checkAppStoreAuth(env: AppStoreEnv): Promise<{ ok: boolean; status: number }> {
	const jwt = await signAppStoreJWT(env);
	const resp = await fetchSubscriptionStatus("api.storekit.itunes.apple.com", "0", jwt);
	return { ok: resp.status !== 401 && resp.status !== 403, status: resp.status };
}

async function fetchSubscriptionStatus(host: string, originalTransactionId: string, jwt: string): Promise<Response> {
	return fetch(`https://${host}/inApps/v1/subscriptions/${originalTransactionId}`, {
		headers: { Authorization: `Bearer ${jwt}` },
	});
}

function decodeJwsPayload(jws: string): Record<string, unknown> {
	const parts = jws.split(".");
	const payloadBytes = fromBase64Url(parts[1]);
	return JSON.parse(new TextDecoder().decode(payloadBytes)) as Record<string, unknown>;
}

async function signAppStoreJWT(env: AppStoreEnv): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	const header = { alg: "ES256", kid: env.APPSTORE_KEY_ID, typ: "JWT" };
	const payload = {
		iss: env.APPSTORE_ISSUER_ID,
		iat: now,
		exp: now + 60,
		aud: "appstoreconnect-v1",
		bid: env.APPSTORE_BUNDLE_ID,
	};

	const encodedHeader = toBase64Url(new TextEncoder().encode(JSON.stringify(header)));
	const encodedPayload = toBase64Url(new TextEncoder().encode(JSON.stringify(payload)));
	const signingInput = `${encodedHeader}.${encodedPayload}`;

	const keyBytes = Uint8Array.from(atob(env.APPSTORE_PRIVATE_KEY), (c) => c.charCodeAt(0));
	const privateKey = await crypto.subtle.importKey(
		"pkcs8",
		keyBytes,
		{ name: "ECDSA", namedCurve: "P-256" },
		false,
		["sign"],
	);
	const signatureBytes = await crypto.subtle.sign(
		{ name: "ECDSA", hash: "SHA-256" },
		privateKey,
		new TextEncoder().encode(signingInput),
	);

	return `${signingInput}.${toBase64Url(new Uint8Array(signatureBytes))}`;
}

function toBase64Url(bytes: Uint8Array): string {
	let str = "";
	for (const b of bytes) str += String.fromCharCode(b);
	return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function fromBase64Url(s: string): Uint8Array {
	const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
	const str = atob(b64);
	return Uint8Array.from(str, (c) => c.charCodeAt(0));
}
