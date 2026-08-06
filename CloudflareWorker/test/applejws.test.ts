import { describe, it, expect, vi } from "vitest";
import { verifyAppleTransactionJWS, WORKER_PROXY_PRODUCT_IDS } from "../src/applejws";

// Fully self-generated, non-Apple test chain (root/intermediate/leaf, openssl-generated,
// matching Apple's real chain shape — P-384 root, P-256 intermediate/leaf — plus the same
// Apple-specific X.509 extension OIDs the library's chain verification checks for:
// 1.2.840.113635.100.6.2.1 on the intermediate, 1.2.840.113635.100.6.11.1 on the leaf.
// This is not Apple data and carries no privacy/security concern: a real Apple-signed
// transaction is always tied to some real purchasing identity, and there is no way to
// construct one that validates against the real pinned Apple root without Apple's private
// signing key. Apple's own app-store-server-library test suite uses the same approach
// (a self-generated testCA.der) for exactly this reason.
const { TEST_ROOT_DER_BASE64 } = vi.hoisted(() => ({
    TEST_ROOT_DER_BASE64:
        "MIICHTCCAaSgAwIBAgIUCJcspxBY3oXA3mnRqG5q/0l3T64wCgYIKoZIzj0EAwMwRjEiMCAGA1UEAwwZVGVzdCBBcHBsZSBSb290IENBIC0gRmFrZTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjYwODA2MDQxMjI3WhcNMzYwODAzMDQxMjI3WjBGMSIwIAYDVQQDDBlUZXN0IEFwcGxlIFJvb3QgQ0EgLSBGYWtlMRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABD0dYT/KgZzW4bkE0fc+1GPxoPvlU5lME1yeKAYn+v9ugTNZYwyrvTBhxXfEzUGjwRxA4fFSqvfNp7krOQzc8gwNup7kXQyajoiH0bI3G+rHfM5tIBHSvNjfJX6wQ8MoqaNTMFEwHQYDVR0OBBYEFLAKPusQS65QCEAHUAwbbtDSPO4sMB8GA1UdIwQYMBaAFLAKPusQS65QCEAHUAwbbtDSPO4sMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwMDZwAwZAIweE6U7pSQdWtIrJ7AlkUU7bFPAu5yXWsWHdU5p7JwHOz61SCjFw8hHvNcvkeL8IFGAjAfgBNPngcVEZSW5Pj4OlNWv6kkES7f9qVNH6dtAXIHB9PIKwwnCweRfQY4UUqs/wA=",
}));

vi.mock("../src/appleRootCertificate", () => ({
    APPLE_ROOT_CA_G3_DER_BASE64: TEST_ROOT_DER_BASE64,
}));

// A well-formed, validly-signed transaction chained to TEST_ROOT_DER_BASE64 above.
const jws =
    "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsIng1YyI6WyJNSUlCMkRDQ0FYNmdBd0lCQWdJVUdza291eGpZRUNZVmRPTHhwS1R3MzEwQVR1SXdDZ1lJS29aSXpqMEVBd0l3UFRFWk1CY0dBMVVFQXd3UVZHVnpkQ0JYVjBSU0lDMGdSbUZyWlRFVE1CRUdBMVVFQ2d3S1FYQndiR1VnU1c1akxqRUxNQWtHQTFVRUJoTUNWVk13SGhjTk1qWXdPREEyTURReE1qSTNXaGNOTWpjd09EQTJNRFF4TWpJM1dqQkZNU0V3SHdZRFZRUUREQmhVWlhOMElHbFVkVzVsY3lCVGRHOXlaU0F0SUVaaGEyVXhFekFSQmdOVkJBb01Da0Z3Y0d4bElFbHVZeTR4Q3pBSkJnTlZCQVlUQWxWVE1Ga3dFd1lIS29aSXpqMENBUVlJS29aSXpqMERBUWNEUWdBRUR0WlNVVXc3a014YTF1blN0Q01HZXdGNWtoMVBrUDVOM0pMbFVCOURvWld3cVRtWG53OUVab1VsUkZDWFZXRmRlZTBnME9yKzYvNTgyeExUeDBVeTJhTlVNRkl3RUFZS0tvWklodmRqWkFZTEFRUUNCUUF3SFFZRFZSME9CQllFRkZncG5iT3p0RUhhaUc5dFg2TlpQL0J3bjAwZE1COEdBMVVkSXdRWU1CYUFGT3Nsa2VNWVl2ODNzRHFBcHVKZUFmM1pkcHgvTUFvR0NDcUdTTTQ5QkFNQ0EwZ0FNRVVDSUZNU1BvejFEM1c5Q003WkhFNGswejlETTZwbDl5OE1uVmV4d0ZyRlhlbWpBaUVBNmVVTXoyWVdlckNvcDdiOUoxZnJCRlBUU3RINVdqYXFTZUE4NGd3UTlSaz0iLCJNSUlDQ1RDQ0FaQ2dBd0lCQWdJVUloa2ZGRXR1RUtqaFdTTUpsRTFoZzlzSlZ3c3dDZ1lJS29aSXpqMEVBd013UmpFaU1DQUdBMVVFQXd3WlZHVnpkQ0JCY0hCc1pTQlNiMjkwSUVOQklDMGdSbUZyWlRFVE1CRUdBMVVFQ2d3S1FYQndiR1VnU1c1akxqRUxNQWtHQTFVRUJoTUNWVk13SGhjTk1qWXdPREEyTURReE1qSTNXaGNOTXpFd09EQTFNRFF4TWpJM1dqQTlNUmt3RndZRFZRUUREQkJVWlhOMElGZFhSRklnTFNCR1lXdGxNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVFzd0NRWURWUVFHRXdKVlV6QlpNQk1HQnlxR1NNNDlBZ0VHQ0NxR1NNNDlBd0VIQTBJQUJMR09ydUdvUjArV0JCVFJVLzFNZXJqTWdadjlGNmE4dFZHYVVnRVNBOWxDdWJBbEJWYkNiOWxrcGFNakFxa3cyOTVhbm9YUUhJLzA2R1FVdjAyUVNNK2paVEJqTUE4R0ExVWRFd0VCL3dRRk1BTUJBZjh3RUFZS0tvWklodmRqWkFZQ0FRUUNCUUF3SFFZRFZSME9CQllFRk9zbGtlTVlZdjgzc0RxQXB1SmVBZjNaZHB4L01COEdBMVVkSXdRWU1CYUFGTEFLUHVzUVM2NVFDRUFIVUF3YmJ0RFNQTzRzTUFvR0NDcUdTTTQ5QkFNREEyY0FNR1FDTUVLMDlRODVjbUlpZmhrMkJkR3gxeG8vRWlIZ3FueG5FT3VZdXZWMFJPZEExcVhZbzhxelovMEVnWE8xdWFia1lRSXdTbXRvd3VoZHJ3QnZaQm9IREkwcXdTUmQ3Y09yV3JIdW9xU2xWSElzc3RqaWUxb3loak1xSW5UM2NFakVBbnBjIiwiTUlJQ0hUQ0NBYVNnQXdJQkFnSVVDSmNzcHhCWTNvWEEzbW5ScUc1cS8wbDNUNjR3Q2dZSUtvWkl6ajBFQXdNd1JqRWlNQ0FHQTFVRUF3d1pWR1Z6ZENCQmNIQnNaU0JTYjI5MElFTkJJQzBnUm1GclpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd0hoY05Nall3T0RBMk1EUXhNakkzV2hjTk16WXdPREF6TURReE1qSTNXakJHTVNJd0lBWURWUVFEREJsVVpYTjBJRUZ3Y0d4bElGSnZiM1FnUTBFZ0xTQkdZV3RsTVJNd0VRWURWUVFLREFwQmNIQnNaU0JKYm1NdU1Rc3dDUVlEVlFRR0V3SlZVekIyTUJBR0J5cUdTTTQ5QWdFR0JTdUJCQUFpQTJJQUJEMGRZVC9LZ1p6VzRia0UwZmMrMUdQeG9QdmxVNWxNRTF5ZUtBWW4rdjl1Z1ROWll3eXJ2VEJoeFhmRXpVR2p3UnhBNGZGU3F2Zk5wN2tyT1F6Yzhnd051cDdrWFF5YWpvaUgwYkkzRytySGZNNXRJQkhTdk5qZkpYNndROE1vcWFOVE1GRXdIUVlEVlIwT0JCWUVGTEFLUHVzUVM2NVFDRUFIVUF3YmJ0RFNQTzRzTUI4R0ExVWRJd1FZTUJhQUZMQUtQdXNRUzY1UUNFQUhVQXdiYnREU1BPNHNNQThHQTFVZEV3RUIvd1FGTUFNQkFmOHdDZ1lJS29aSXpqMEVBd01EWndBd1pBSXdlRTZVN3BTUWRXdElySjdBbGtVVTdiRlBBdTV5WFdzV0hkVTVwN0p3SE96NjFTQ2pGdzhoSHZOY3ZrZUw4SUZHQWpBZmdCTlBuZ2NWRVpTVzVQajRPbE5XdjZra0VTN2Y5cVZOSDZkdEFYSUhCOVBJS3d3bkN3ZVJmUVk0VVVxcy93QT0iXX0.eyJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiIxMDAwMDAwMDAwMDAwMDAxIiwidHJhbnNhY3Rpb25JZCI6IjIwMDAwMDAwMDAwMDAwMDEiLCJidW5kbGVJZCI6Im9yZy5sYXJuZXIuU0ZUcmFuc2l0V2F0Y2giLCJwcm9kdWN0SWQiOiJvcmcubGFybmVyLlNGVHJhbnNpdFdhdGNoLnByb3h5Lm1vbnRobHkiLCJlbnZpcm9ubWVudCI6IlNhbmRib3giLCJleHBpcmVzRGF0ZSI6MTc4ODU4MTYwNjEwOCwic2lnbmVkRGF0ZSI6MTc4NTk4OTYwNjEwOH0.V1HHfbRd1UgNkXHEj5xoO9pyEeLpA408aHJaEt1U_9QsxZ7xbMau2ROm4UhWooOl8Z4BswHGhX7aXk7qrKbAJA";

// An independently well-formed but differently-rooted transaction (not chained to
// TEST_ROOT_DER_BASE64 above) — used only to prove the "untrusted root" rejection is
// real and specific, not a byproduct of some other broken check.
const OTHER_ROOT_CHAIN_JWS =
    "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsIng1YyI6WyJNSUlCM1RDQ0FZS2dBd0lCQWdJVWU1UWhwRDd1eG5wQ0NUTlhIRE1jSERjMlJKOHdDZ1lJS29aSXpqMEVBd0l3UHpFYk1Ca0dBMVVFQXd3U1ZHVnpkQ0JYVjBSU0lFSWdMU0JHWVd0bE1STXdFUVlEVlFRS0RBcEJjSEJzWlNCSmJtTXVNUXN3Q1FZRFZRUUdFd0pWVXpBZUZ3MHlOakE0TURZd05ESXhNalJhRncweU56QTRNRFl3TkRJeE1qUmFNRWN4SXpBaEJnTlZCQU1NR2xSbGMzUWdhVlIxYm1WeklGTjBiM0psSUVJZ0xTQkdZV3RsTVJNd0VRWURWUVFLREFwQmNIQnNaU0JKYm1NdU1Rc3dDUVlEVlFRR0V3SlZVekJaTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEEwSUFCSldKV2Rma3lnMEQ1ck10azU0N21XWEI1Q0Y1K1UzT0NSS1lwY2R3ZXFZMW9KSnRvV1pqYmJhdTF3TTRHNXNzRmZtbU9DVktVTGpoaVlqZlhnYVFXZHFqVkRCU01CQUdDaXFHU0liM1kyUUdDd0VFQWdVQU1CMEdBMVVkRGdRV0JCU2JxM21BN252NU9GelU1bU5sUHdvTlhNTm1FVEFmQmdOVkhTTUVHREFXZ0JUTTJsTkFMTXpPWm9vcys0WmkxT2tZTXBpbU1UQUtCZ2dxaGtqT1BRUURBZ05KQURCR0FpRUF4TENIWTNDNHpCVWJmcUE0NEVWL3BUcDdxTG9Ec1p2NCtaN05PRU9DZ0xFQ0lRRG9TY0ZwRDFZRm53TXM2S0VKZkpDeE5WeEFFeS8rZzVxWWplMnVKZlpBMVE9PSIsIk1JSUNEakNDQVpTZ0F3SUJBZ0lVQ2ZETDRac3NGbnRkUXExSUp5SmVWUnB5R1Zrd0NnWUlLb1pJemowRUF3TXdTREVrTUNJR0ExVUVBd3diVkdWemRDQkJjSEJzWlNCU2IyOTBJRU5CSUVJZ0xTQkdZV3RsTVJNd0VRWURWUVFLREFwQmNIQnNaU0JKYm1NdU1Rc3dDUVlEVlFRR0V3SlZVekFlRncweU5qQTRNRFl3TkRJeE1ETmFGdzB6TVRBNE1EVXdOREl4TUROYU1EOHhHekFaQmdOVkJBTU1FbFJsYzNRZ1YxZEVVaUJDSUMwZ1JtRnJaVEVUTUJFR0ExVUVDZ3dLUVhCd2JHVWdTVzVqTGpFTE1Ba0dBMVVFQmhNQ1ZWTXdXVEFUQmdjcWhrak9QUUlCQmdncWhrak9QUU1CQndOQ0FBVE9acm5mRHZWQkhGQXVqR3VGQ2o2U0NDL1BUUDYrSDZQa1N1SysvNlN1dHNaeWRoOG5kY3RZejQwcHNrQ1pWRmZZT2p2TUJxRHQ2VnQ2ZlN6ZWhITWVvMlV3WXpBUEJnTlZIUk1CQWY4RUJUQURBUUgvTUJBR0NpcUdTSWIzWTJRR0FnRUVBZ1VBTUIwR0ExVWREZ1FXQkJUTTJsTkFMTXpPWm9vcys0WmkxT2tZTXBpbU1UQWZCZ05WSFNNRUdEQVdnQlNDVWFybHRxbm1Wcjd4K0RwWWYvS2ZiR0tPMGpBS0JnZ3Foa2pPUFFRREF3Tm9BREJsQWpCemxqSjl4RjRZdytIaFd4dEZDY3pmU2tzQmJwU3I4Y0YyNGxjZ3VNRlNRQnhiMCt1bUxlMTdRa0xPcHZEcUNGb0NNUUQzSkdyZVpXdmtTREZWV29zVkYvL2owOUZWRXhxaEJGM0ZtQ1V6cmFlb3FwbHNsR2xPYkRxL1IwNnRaUmVIQ1YwPSIsIk1JSUNJekNDQWFpZ0F3SUJBZ0lVSUxJYjh6Nlp3eDJGckZnVVd5Mnd1UGVsbEhjd0NnWUlLb1pJemowRUF3TXdTREVrTUNJR0ExVUVBd3diVkdWemRDQkJjSEJzWlNCU2IyOTBJRU5CSUVJZ0xTQkdZV3RsTVJNd0VRWURWUVFLREFwQmNIQnNaU0JKYm1NdU1Rc3dDUVlEVlFRR0V3SlZVekFlRncweU5qQTRNRFl3TkRJd016bGFGdzB6TmpBNE1ETXdOREl3TXpsYU1FZ3hKREFpQmdOVkJBTU1HMVJsYzNRZ1FYQndiR1VnVW05dmRDQkRRU0JDSUMwZ1JtRnJaVEVUTUJFR0ExVUVDZ3dLUVhCd2JHVWdTVzVqTGpFTE1Ba0dBMVVFQmhNQ1ZWTXdkakFRQmdjcWhrak9QUUlCQmdVcmdRUUFJZ05pQUFSL2dTYms4VFVrN2V3a2NRK3lRbnpudzI1M0J4SUZEU3BJMDVmZExDblFUd2F6NmlXeXV5cFNyMmg1N1E5aVcySVdYYVdLQnMxNFlTNWJkN2RIS3FlOERxVnZJMjluVGV5RVZEeE0vZm5JVWlTZlQzZGFHWmZ6My9LY1VTQzhHQjZqVXpCUk1CMEdBMVVkRGdRV0JCU0NVYXJsdHFubVZyN3grRHBZZi9LZmJHS08wakFmQmdOVkhTTUVHREFXZ0JTQ1Vhcmx0cW5tVnI3eCtEcFlmL0tmYkdLTzBqQVBCZ05WSFJNQkFmOEVCVEFEQVFIL01Bb0dDQ3FHU000OUJBTURBMmtBTUdZQ01RRDcreFBkM2tPR3ZLSjcwK3JTY2NhOUpIT1ZJY2w2QVZRR0tsZUI0TFBrTnhBbDRIS1NJMXI3ak1LSHpLODE4TzhDTVFDNHNzaEplNUM4bUs3VWFJQmRKTVBHZ2QzZVZQMnFGZG1JWHo4RXg3NndKRjNOL0tIRVlnOE9vZDNydW96b3FhZz0iXX0.eyJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiIxMDAwMDAwMDAwMDAwMDAxIiwidHJhbnNhY3Rpb25JZCI6IjIwMDAwMDAwMDAwMDAwMDEiLCJidW5kbGVJZCI6Im9yZy5sYXJuZXIuU0ZUcmFuc2l0V2F0Y2giLCJwcm9kdWN0SWQiOiJvcmcubGFybmVyLlNGVHJhbnNpdFdhdGNoLnByb3h5Lm1vbnRobHkiLCJlbnZpcm9ubWVudCI6IlNhbmRib3giLCJleHBpcmVzRGF0ZSI6MTc4ODY2ODAwNjEwOCwic2lnbmVkRGF0ZSI6MTc4NjA3NjAwNjEwOH0.wpIqsX4RoxELkci4h98iocxRHIs5Y-a72QolcnPiWSBenmdzrii_QfRvaKMn7Q5GVu_14gi6RRwsEAZnGODhXw";

const OPTS = { bundleId: "org.larner.SFTransitWatch", appAppleId: 1234567890, productIds: WORKER_PROXY_PRODUCT_IDS };

describe("verifyAppleTransactionJWS", () => {
    it("accepts a well-formed, validly-signed transaction chained to the trusted test root", async () => {
        const result = await verifyAppleTransactionJWS(jws, OPTS);
        expect(result.ok).toBe(true);
        if (!result.ok) return;
        expect(result.payload.originalTransactionId).toBe("1000000000000001");
        expect(result.payload.transactionId).toBe("2000000000000001");
        expect(result.payload.bundleId).toBe("org.larner.SFTransitWatch");
        expect(result.payload.productId).toBe("org.larner.SFTransitWatch.proxy.monthly");
        expect(result.payload.environment).toBe("Sandbox");
        expect(result.payload.expiresDateMs).toBe(1788581606108);
    });

    it("rejects when the payload has been tampered with", async () => {
        const [h, p, s] = jws.split(".");
        const flipped = p.slice(0, -4) + (p.slice(-4) === "AAAA" ? "BBBB" : "AAAA");
        const result = await verifyAppleTransactionJWS(`${h}.${flipped}.${s}`, OPTS);
        expect(result.ok).toBe(false);
    });

    it("rejects when the signature has been tampered with", async () => {
        const [h, p, s] = jws.split(".");
        const flipped = s.slice(0, -4) + (s.slice(-4) === "AAAA" ? "BBBB" : "AAAA");
        const result = await verifyAppleTransactionJWS(`${h}.${p}.${flipped}`, OPTS);
        expect(result.ok).toBe(false);
    });

    it("rejects a bundleId that doesn't match the configured app", async () => {
        const result = await verifyAppleTransactionJWS(jws, { ...OPTS, bundleId: "com.evil.app" });
        expect(result.ok).toBe(false);
    });

    it("rejects a productId not in the configured list", async () => {
        const result = await verifyAppleTransactionJWS(jws, { ...OPTS, productIds: ["org.larner.SFTransitWatch.other"] });
        expect(result.ok).toBe(false);
    });

    it("rejects a malformed JWS", async () => {
        const result = await verifyAppleTransactionJWS("not-a-jws", OPTS);
        expect(result.ok).toBe(false);
    });

    it("rejects a JWS whose chain roots in a certificate other than the trusted one", async () => {
        const result = await verifyAppleTransactionJWS(OTHER_ROOT_CHAIN_JWS, OPTS);
        expect(result.ok).toBe(false);
    });
});
