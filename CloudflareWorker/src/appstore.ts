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
	// Retry in sandbox on 404 (transaction unknown in production) and on 401
	// (a pre-release/TestFlight app has no production App Store Server API
	// presence, so production rejects the token even though it's valid in
	// sandbox). Production is still tried first so real subscriptions verify
	// correctly once the app ships.
	if (prodResp.status === 404 || prodResp.status === 401) {
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
		console.warn(JSON.stringify({ source: "verify-sub", reason: "no_last_transaction", usedSandbox, dataCount: data.data?.length ?? 0, txId: originalTransactionId, raw: JSON.stringify(data).slice(0, 500) }));
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
	// Production first; fall back to sandbox on 401/403 so a pre-release app
	// (which has no production presence yet) still reports healthy.
	let resp = await fetchSubscriptionStatus("api.storekit.itunes.apple.com", "0", jwt);
	let host = "production";
	if (resp.status === 401 || resp.status === 403) {
		resp = await fetchSubscriptionStatus("api.storekit-sandbox.itunes.apple.com", "0", jwt);
		host = "sandbox";
	}
	const ok = resp.status !== 401 && resp.status !== 403;
	if (!ok) {
		const body = await resp.text().catch(() => "");
		console.warn(JSON.stringify({ source: "appstore-auth-check", status: resp.status, host, kid: env.APPSTORE_KEY_ID, iss: env.APPSTORE_ISSUER_ID, bid: env.APPSTORE_BUNDLE_ID, body: body.slice(0, 300) }));
	}
	return { ok, status: resp.status };
}

async function fetchSubscriptionStatus(host: string, originalTransactionId: string, jwt: string): Promise<Response> {
	// Encode the id into the path: it is caller-supplied, and an unescaped "../" or "?"
	// would let it redirect this JWT-authenticated request to an arbitrary App Store
	// Server API endpoint. handleSelfProvision also validates it as a numeric string.
	return fetch(`https://${host}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`, {
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
