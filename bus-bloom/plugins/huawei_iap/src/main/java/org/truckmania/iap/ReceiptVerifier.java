package org.truckmania.iap;

import java.nio.charset.StandardCharsets;
import java.security.PublicKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.PSSParameterSpec;

/** Cryptographic and identity checks kept independent of Android for regression tests. */
public final class ReceiptVerifier {
    private ReceiptVerifier() {}

    public static boolean verify(String content, byte[] signatureBytes, PublicKey key, String algorithm) {
        if (content == null || content.isEmpty() || signatureBytes == null || signatureBytes.length == 0
                || !(key instanceof RSAPublicKey) || ((RSAPublicKey) key).getModulus().bitLength() < 2048) return false;
        String name = algorithm == null || algorithm.isEmpty() ? "SHA256WithRSA" : algorithm;
        try {
            Signature verifier;
            if (name.equalsIgnoreCase("SHA256WithRSA")) {
                verifier = Signature.getInstance("SHA256WithRSA");
            } else if (name.equalsIgnoreCase("SHA256WithRSA/PSS")) {
                try { verifier = Signature.getInstance("RSASSA-PSS"); }
                catch (java.security.NoSuchAlgorithmException ignored) {
                    verifier = Signature.getInstance("SHA256withRSA/PSS");
                }
                verifier.setParameter(new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1));
            } else return false; // Never let an untrusted response choose SHA1, MD5, or NONE.
            verifier.initVerify(key);
            verifier.update(content.getBytes(StandardCharsets.UTF_8));
            return verifier.verify(signatureBytes);
        } catch (Exception ignored) { return false; }
    }

    public static boolean identityMatches(String actualApp, String actualPackage, String actualProduct,
                                          int actualType, String expectedApp, String expectedPackage,
                                          String expectedProduct, int expectedType) {
        return expectedApp != null && !expectedApp.isEmpty() && expectedApp.equals(actualApp)
                && expectedPackage != null && !expectedPackage.isEmpty() && expectedPackage.equals(actualPackage)
                && expectedProduct != null && !expectedProduct.isEmpty() && expectedProduct.equals(actualProduct)
                && (expectedType == 0 || expectedType == 1) && actualType == expectedType;
    }

    // Huawei receipt price = actual price * 100; ProductInfo uses * 1,000,000.
    public static boolean priceMatches(long receiptPrice, String receiptCurrency, long micros, String currency) {
        return receiptPrice >= 0 && micros >= 0 && micros % 10000 == 0
                && receiptPrice == micros / 10000 && currency != null
                && currency.matches("[A-Z]{3}") && currency.equals(receiptCurrency);
    }
}
