import { describe, it, expect } from "vitest";
import { X509Certificate } from "node:crypto";
import { APPLE_ROOT_CA_G3_DER_BASE64 } from "../src/appleRootCertificate";

describe("APPLE_ROOT_CA_G3_DER_BASE64", () => {
    it("decodes to a certificate matching Apple's published SHA-256 fingerprint", () => {
        const cert = new X509Certificate(Buffer.from(APPLE_ROOT_CA_G3_DER_BASE64, "base64"));
        expect(cert.fingerprint256).toBe(
            "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79",
        );
    });

    it("is Apple's self-signed root certificate", () => {
        const cert = new X509Certificate(Buffer.from(APPLE_ROOT_CA_G3_DER_BASE64, "base64"));
        expect(cert.subject).toContain("Apple Root CA - G3");
        expect(cert.subject).toContain("Apple Inc.");
        expect(cert.checkIssued(cert)).toBe(true);
    });
});
