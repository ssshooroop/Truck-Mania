package org.truckmania.iap;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.PSSParameterSpec;

/** Real ephemeral cryptographic signatures; no real account keys or store data. */
public final class ReceiptVerifierTest {
    private static void require(boolean value,String name) { if(!value)throw new AssertionError(name); }
    public static void main(String[] args) throws Exception {
        KeyPairGenerator generator=KeyPairGenerator.getInstance("RSA"); generator.initialize(2048);
        KeyPair key=generator.generateKeyPair(), other=generator.generateKeyPair();
        String data="{\"productId\":\"test-coins\",\"purchaseState\":0}";
        Signature sign=Signature.getInstance("SHA256WithRSA"); sign.initSign(key.getPrivate());
        sign.update(data.getBytes(StandardCharsets.UTF_8)); byte[] signature=sign.sign();
        require(ReceiptVerifier.verify(data,signature,key.getPublic(),null),"default SHA256 signature");
        require(ReceiptVerifier.verify(data,signature,key.getPublic(),"SHA256WithRSA"),"explicit SHA256");
        require(!ReceiptVerifier.verify(data+" ",signature,key.getPublic(),null),"tampered signed bytes");
        require(!ReceiptVerifier.verify(data,signature,other.getPublic(),null),"wrong public key");
        require(!ReceiptVerifier.verify(data,signature,key.getPublic(),"SHA1withRSA"),"algorithm downgrade rejected");
        require(!ReceiptVerifier.verify(data,new byte[0],key.getPublic(),null),"empty signature rejected");
        sign=Signature.getInstance("RSASSA-PSS");
        sign.setParameter(new PSSParameterSpec("SHA-256","MGF1",MGF1ParameterSpec.SHA256,32,1));
        sign.initSign(key.getPrivate()); sign.update(data.getBytes(StandardCharsets.UTF_8));
        require(ReceiptVerifier.verify(data,sign.sign(),key.getPublic(),"SHA256WithRSA/PSS"),"allowlisted PSS");
        require(ReceiptVerifier.identityMatches("1234","game.hw","coins",0,"1234","game.hw","coins",0),"matching application");
        require(!ReceiptVerifier.identityMatches("9999","game.hw","coins",0,"1234","game.hw","coins",0),"cross app rejected");
        require(!ReceiptVerifier.identityMatches("1234","game","coins",0,"1234","game.hw","coins",0),"cross package rejected");
        require(!ReceiptVerifier.identityMatches("1234","game.hw","other",0,"1234","game.hw","coins",0),"cross product rejected");
        require(!ReceiptVerifier.identityMatches("1234","game.hw","coins",1,"1234","game.hw","coins",0),"wrong product kind");
        require(ReceiptVerifier.priceMatches(199,"USD",1990000,"USD"),"receipt hundredths to micros");
        require(!ReceiptVerifier.priceMatches(1,"USD",1990000,"USD"),"underpayment rejected");
        require(!ReceiptVerifier.priceMatches(199,"EUR",1990000,"USD"),"wrong currency rejected");
        require(!ReceiptVerifier.priceMatches(199,"USD",1990001,"USD"),"no price rounding");
        System.out.println("PASS: receipt signatures, tampering, key/algorithm rejection, app/package/product/type, price/currency");
    }
}
