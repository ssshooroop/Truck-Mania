package org.truckmania.iap;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;
import com.huawei.hms.common.ApiException;
import com.huawei.hms.iap.Iap;
import com.huawei.hms.iap.IapApiException;
import com.huawei.hms.iap.IapClient;
import com.huawei.hms.iap.entity.*;
import com.huawei.hms.iap.util.IapClientHelper;
import com.huawei.hms.support.api.client.Status;
import com.huawei.hms.utils.Util;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.*;

/** HMS calls and mutable state are confined to Android's main thread. No receipt/key logging. */
public final class TruckManiaIap extends GodotPlugin {
    private static final String LOG_TAG = "TruckManiaIap";
    private static final int ENV_REQUEST = 41701;
    private static final long NETWORK_TIMEOUT_MS = 90000;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Map<String, Product> catalog = new LinkedHashMap<>();
    private final Map<String, Product> byStoreId = new HashMap<>();
    private final Map<String, ProductInfo> prices = new HashMap<>();
    private final Map<String, Verified> verifiedTokens = new HashMap<>();
    private final Set<String> consuming = new HashSet<>();
    private final Map<Integer, Checkout> checkouts = new HashMap<>();
    private IapClient client;
    private PublicKey publicKey;
    private String appId = "", packageName = "";
    private boolean configured, ready, envChecking, envResolutionAttempted, destroyed;
    private int nextActivityRequest = 42000, productQuery, environmentSerial;
    private Checkout activeCheckout;
    private OwnedScan activeScan;

    private static final class Product {
        final String id, storeId; final int type;
        Product(String id, String storeId, int type) { this.id=id; this.storeId=storeId; this.type=type; }
    }
    private static final class Checkout {
        final Product product; final int requestId; final ProductInfo price;
        final String payload = UUID.randomUUID().toString();
        boolean finished;
        Checkout(Product product, int requestId, ProductInfo price) {
            this.product=product; this.requestId=requestId; this.price=price;
        }
    }
    private static final class Verified {
        final Product product; final String token, order;
        Verified(Product product, String token, String order) { this.product=product; this.token=token; this.order=order; }
    }
    private static final class OwnedScan {
        final int requestId; final String source;
        final Set<String> pages = new HashSet<>(), receipts = new HashSet<>();
        boolean finished, failed; int pageCount;
        OwnedScan(int requestId, String source) { this.requestId=requestId; this.source=source; }
    }

    public TruckManiaIap(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "TruckManiaIap"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
                new SignalInfo("env_ready", Boolean.class, String.class),
                new SignalInfo("products_loaded", String.class, String.class),
                new SignalInfo("purchase_verified", String.class),
                new SignalInfo("operation_finished", Integer.class, String.class, String.class),
                new SignalInfo("consumed", String.class, Boolean.class, String.class)));
    }
    private void signal(String name, Object... args) {
        if (destroyed) return;
        // Only fixed diagnostic codes and numeric SDK statuses are permitted here.
        // Never log the other signals: they can contain receipts, tokens or orders.
        if ("env_ready".equals(name) && args.length==2) {
            Log.i(LOG_TAG,"env_ready="+Boolean.TRUE.equals(args[0])+" code="+diagnosticCode(args[1]));
        } else if ("products_loaded".equals(name) && args.length==2 && !"".equals(args[1])) {
            Log.w(LOG_TAG,"products_loaded code="+diagnosticCode(args[1]));
        }
        emitSignal(name,args);
    }
    private static String diagnosticCode(Object value) {
        if (!(value instanceof String)) return "unknown";
        String code=(String)value;
        return code.isEmpty()?"ok":code.matches("[a-zA-Z0-9_-]{1,80}")?code:"unknown";
    }
    private void done(int id, String status, String error) { signal("operation_finished",id,status,error); }
    private static boolean empty(String s) { return s==null || s.isEmpty(); }
    private static String error(Exception e) {
        return e instanceof ApiException ? "huawei_"+((ApiException)e).getStatusCode() : "sdk_error";
    }
    private static int errorCode(Exception e) { return e instanceof ApiException ? ((ApiException)e).getStatusCode() : -1; }

    @UsedByGodot public void initialize(String applicationId, String rsaPublicKey, String catalogJson) {
        ui.post(() -> {
            if (configured) { envResolutionAttempted=false; checkEnvironment(); return; }
            try {
                Activity activity=getActivity();
                if (activity==null || applicationId==null || !applicationId.matches("[1-9][0-9]{3,30}")) throw new IllegalArgumentException();
                String encoded=rsaPublicKey.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replaceAll("\\s", "");
                PublicKey key=KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(Base64.decode(encoded,Base64.DEFAULT)));
                if (!(key instanceof RSAPublicKey) || ((RSAPublicKey)key).getModulus().bitLength()<2048) throw new IllegalArgumentException();
                Bundle meta=activity.getPackageManager().getApplicationInfo(activity.getPackageName(),PackageManager.GET_META_DATA).metaData;
                if (meta==null || !("appid="+applicationId).equals(meta.getString("com.huawei.hms.client.appid"))) {
                    signal("env_ready",false,"app_metadata_mismatch"); return;
                }
                if (!applicationId.equals(Util.getAppId(activity))) { signal("env_ready",false,"sdk_app_id_mismatch"); return; }
                JSONArray input=new JSONArray(catalogJson);
                if (input.length()==0 || input.length()>100) throw new IllegalArgumentException();
                Map<String,Product> checked=new LinkedHashMap<>(), stores=new HashMap<>();
                for (int i=0;i<input.length();i++) {
                    JSONObject row=input.getJSONObject(i);
                    String id=row.getString("id"), store=row.optString("product_id",row.optString("store_id",""));
                    int type=row.getInt("type");
                    if (empty(id) || empty(store) || (type!=0 && type!=1) || checked.containsKey(id) || stores.containsKey(store)) throw new IllegalArgumentException();
                    Product p=new Product(id,store,type); checked.put(id,p); stores.put(store,p);
                }
                publicKey=key; appId=applicationId; packageName=activity.getPackageName();
                catalog.putAll(checked); byStoreId.putAll(stores);
                client=Iap.getIapClient(activity);
                client.enablePendingPurchase();
                configured=true; checkEnvironment();
            } catch (Exception e) {
                String exceptionClass=diagnosticCode(e.getClass().getSimpleName());
                Log.w(LOG_TAG,"configuration_invalid class="+exceptionClass);
                signal("env_ready",false,"configuration_invalid_"+exceptionClass);
            }
        });
    }

    private void checkEnvironment() {
        if (!configured || destroyed || envChecking || getActivity()==null) return;
        envChecking=true; ready=false;
        int serial=++environmentSerial;
        ui.postDelayed(() -> { if (envChecking && environmentSerial==serial) { envChecking=false; signal("env_ready",false,"environment_timeout"); } },NETWORK_TIMEOUT_MS);
        try {
            client.isEnvReady().addOnSuccessListener(result -> ui.post(() -> {
                if(environmentSerial!=serial)return;
                envChecking=false;
                if (result.getReturnCode()!=OrderStatusCode.ORDER_STATE_SUCCESS) { signal("env_ready",false,"huawei_"+result.getReturnCode()); return; }
                ready=true; envResolutionAttempted=false;
                signal("env_ready",true,""); queryProducts();
            })).addOnFailureListener(e -> ui.post(() -> {
                if(environmentSerial!=serial)return;
                envChecking=false;
                Log.w(LOG_TAG,"environment_request code="+diagnosticCode(error(e)));
                if (e instanceof IapApiException && !envResolutionAttempted && getActivity()!=null) {
                    Status status=((IapApiException)e).getStatus();
                    if (status!=null && status.hasResolution()) {
                        try { envResolutionAttempted=true; status.startResolutionForResult(getActivity(),ENV_REQUEST); return; }
                        catch (Exception ignored) { /* Report below without exposing response payloads. */ }
                    }
                }
                signal("env_ready",false,error(e));
            }));
        } catch (Exception e) { envChecking=false; signal("env_ready",false,error(e)); }
    }

    @UsedByGodot public void query_products() { ui.post(() -> { if(!ready)envResolutionAttempted=false; queryProducts(); }); }
    private void queryProducts() {
        if (!ready) { signal("products_loaded","[]","unavailable"); if (configured) checkEnvironment(); return; }
        if (productQuery!=0) return;
        int ticket=++querySerial; productQuery=ticket;
        Map<String,ProductInfo> found=new HashMap<>();
        ui.postDelayed(() -> { if (productQuery==ticket) { productQuery=0; prices.clear(); signal("products_loaded","[]","product_timeout"); } },NETWORK_TIMEOUT_MS);
        queryProductType(ticket,0,found);
    }
    private int querySerial;
    private void queryProductType(int ticket,int type,Map<String,ProductInfo> found) {
        if (productQuery!=ticket) return;
        if (type>1) {
            productQuery=0; prices.clear(); prices.putAll(found); signal("products_loaded",productJson(),"");
            if (activeCheckout==null && activeScan==null) beginScan(0,"recovery");
            return;
        }
        List<String> ids=new ArrayList<>(); for (Product p:catalog.values()) if (p.type==type) ids.add(p.storeId);
        if (ids.isEmpty()) { queryProductType(ticket,type+1,found); return; }
        ProductInfoReq req=new ProductInfoReq(); req.setPriceType(type); req.setProductIds(ids);
        try {
            client.obtainProductInfo(req).addOnSuccessListener(result -> ui.post(() -> {
                if (productQuery!=ticket) return;
                if (result.getReturnCode()!=0 || result.getProductInfoList()==null) { productQuery=0; prices.clear(); signal("products_loaded","[]",result.getReturnCode()!=0?"huawei_"+result.getReturnCode():"product_query_failed"); return; }
                for (ProductInfo info:result.getProductInfoList()) {
                    Product p=byStoreId.get(info.getProductId());
                    if (p!=null && p.type==info.getPriceType() && !empty(info.getPrice()) && !empty(info.getCurrency()) && info.getMicrosPrice()>=0) found.put(p.id,info);
                }
                queryProductType(ticket,type+1,found);
            })).addOnFailureListener(e -> ui.post(() -> { if (productQuery==ticket) { productQuery=0; prices.clear(); signal("products_loaded","[]",error(e)); } }));
        } catch (Exception e) { productQuery=0; prices.clear(); signal("products_loaded","[]",error(e)); }
    }
    private String productJson() {
        JSONArray output=new JSONArray();
        try {
            for (Product p:catalog.values()) {
                ProductInfo info=prices.get(p.id); if (info==null) continue;
                output.put(new JSONObject().put("id",p.id).put("product_id",p.storeId).put("type",p.type)
                        .put("price",info.getPrice()).put("currency",info.getCurrency()).put("micros_price",info.getMicrosPrice())
                        .put("title",info.getProductName()));
            }
        } catch (Exception ignored) { return "[]"; }
        return output.toString();
    }

    @UsedByGodot public void purchase(String logicalId,int requestId) {
        ui.post(() -> {
            Product p=catalog.get(logicalId); ProductInfo price=prices.get(logicalId);
            if (!ready || p==null || price==null || getActivity()==null || requestId<=0) {
                done(requestId,"unavailable","product_unavailable");
                if(configured && !ready) { envResolutionAttempted=false; checkEnvironment(); }
                return;
            }
            if (activeCheckout!=null || activeScan!=null) { done(requestId,"busy","operation_in_progress"); return; }
            Checkout checkout=new Checkout(p,requestId,price); activeCheckout=checkout;
            // A lost callback must not lock the shop. Late signed results are still delivered as recovery.
            ui.postDelayed(() -> finishCheckout(checkout,"pending","purchase_timeout"),300000);
            ProductInfoReq req=new ProductInfoReq(); req.setPriceType(p.type); req.setProductIds(Collections.singletonList(p.storeId));
            try {
                client.obtainProductInfo(req).addOnSuccessListener(result -> ui.post(() -> {
                    if (checkout.finished) return;
                    ProductInfo fresh=null;
                    if (result.getReturnCode()==0 && result.getProductInfoList()!=null) for (ProductInfo info:result.getProductInfoList()) if (p.storeId.equals(info.getProductId()) && p.type==info.getPriceType()) fresh=info;
                    if (fresh==null) { finishCheckout(checkout,"unavailable","product_unavailable"); return; }
                    prices.put(p.id,fresh);
                    if (fresh.getMicrosPrice()!=price.getMicrosPrice() || !Objects.equals(fresh.getCurrency(),price.getCurrency())) {
                        signal("products_loaded",productJson(),""); finishCheckout(checkout,"failed","price_changed"); return;
                    }
                    launchCheckout(checkout);
                })).addOnFailureListener(e -> ui.post(() -> failCheckout(checkout,e)));
            } catch (Exception e) { failCheckout(checkout,e); }
        });
    }
    private void launchCheckout(Checkout checkout) {
        PurchaseIntentReq req=new PurchaseIntentReq(); req.setPriceType(checkout.product.type);
        req.setProductId(checkout.product.storeId); req.setDeveloperPayload(checkout.payload);
        // Omit signatureAlgorithm: Huawei specifies default SHA256WithRSA for client verification.
        try {
            client.createPurchaseIntent(req).addOnSuccessListener(result -> ui.post(() -> {
                if (checkout.finished) return;
                Status status=result.getStatus();
                if (status==null || !status.hasResolution() || getActivity()==null) { finishCheckout(checkout,"failed","checkout_unavailable"); return; }
                int code=nextActivityRequest++;
                if (nextActivityRequest>60000) nextActivityRequest=42000;
                while (checkouts.containsKey(code)) code=nextActivityRequest++;
                checkouts.put(code,checkout);
                try { status.startResolutionForResult(getActivity(),code); }
                catch (Exception e) { checkouts.remove(code); finishCheckout(checkout,"failed","checkout_launch_failed"); }
            })).addOnFailureListener(e -> ui.post(() -> failCheckout(checkout,e)));
        } catch (Exception e) { failCheckout(checkout,e); }
    }
    private void failCheckout(Checkout checkout,Exception e) {
        if (checkout.finished) return;
        int code=errorCode(e);
        if (code==OrderStatusCode.ORDER_PRODUCT_OWNED) { recoverCheckout(checkout); return; }
        if (code==OrderStatusCode.ORDER_HWID_NOT_LOGIN) { ready=false; envResolutionAttempted=false; checkEnvironment(); }
        finishCheckout(checkout,code==OrderStatusCode.ORDER_STATE_CANCEL?"cancelled":code==OrderStatusCode.ORDER_STATE_PENDING?"pending":"failed",error(e));
    }
    private void finishCheckout(Checkout checkout,String status,String error) {
        if (checkout.finished) return;
        checkout.finished=true; if (activeCheckout==checkout) activeCheckout=null;
        done(checkout.requestId,status,error);
    }
    private void recoverCheckout(Checkout checkout) {
        checkout.finished=true; if (activeCheckout==checkout) activeCheckout=null;
        beginScan(checkout.requestId,"recovery");
    }

    @Override public void onMainActivityResult(int requestCode,int resultCode,Intent data) {
        ui.post(() -> {
            if (requestCode==ENV_REQUEST) {
                int code=data==null?OrderStatusCode.ORDER_STATE_DEFAULT_CODE:IapClientHelper.parseRespCodeFromIntent(data);
                Log.i(LOG_TAG,"environment_resolution code="+code+" activity_result="+resultCode);
                if (data!=null && code==OrderStatusCode.ORDER_STATE_SUCCESS) checkEnvironment();
                else signal("env_ready",false,data==null || code==OrderStatusCode.ORDER_STATE_CANCEL
                        ?"environment_resolution_cancelled":"huawei_"+code);
                return;
            }
            Checkout checkout=checkouts.remove(requestCode); if (checkout==null) return;
            if (data==null) { finishCheckout(checkout,"cancelled","cancelled"); return; }
            try {
                PurchaseResultInfo result=client.parsePurchaseResultInfoFromIntent(data);
                int code=result.getReturnCode();
                if (code==OrderStatusCode.ORDER_PRODUCT_OWNED) { recoverCheckout(checkout); return; }
                if (code==OrderStatusCode.ORDER_STATE_CANCEL) { finishCheckout(checkout,"cancelled","cancelled"); return; }
                if (code==OrderStatusCode.ORDER_STATE_PENDING) {
                    // Some pending responses carry a signed placed order. Authenticate it too,
                    // but never authorize delivery from this non-success response code.
                    if (!empty(result.getInAppPurchaseData())) {
                        if (!ReceiptVerifier.verify(result.getInAppPurchaseData(),Base64.decode(result.getInAppDataSignature(),Base64.DEFAULT),publicKey,result.getSignatureAlgorithm())) throw new SecurityException();
                        JSONObject pending=new JSONObject(result.getInAppPurchaseData());
                        if (pending.getInt("purchaseState")!=3 || !ReceiptVerifier.identityMatches(pending.getString("applicationId"),pending.getString("packageName"),pending.getString("productId"),pending.getInt("kind"),appId,packageName,checkout.product.storeId,checkout.product.type)
                                || !checkout.payload.equals(pending.getString("developerPayload"))) throw new SecurityException();
                    }
                    finishCheckout(checkout,"pending","payment_pending"); return;
                }
                if (code!=OrderStatusCode.ORDER_STATE_SUCCESS) { finishCheckout(checkout,"failed","huawei_"+code); return; }
                int state=verifyAndDeliver(result.getInAppPurchaseData(),result.getInAppDataSignature(),result.getSignatureAlgorithm(),
                        checkout.finished?"recovery":"purchase",checkout.requestId,checkout,null);
                finishCheckout(checkout,state==3?"pending":"verified",state==3?"payment_pending":"");
            } catch (Exception ignored) { finishCheckout(checkout,"failed","receipt_verification_failed"); }
        });
    }

    @UsedByGodot public void restore(int requestId) { ui.post(() -> { if(!ready)envResolutionAttempted=false; beginScan(requestId,"restore"); }); }
    private void beginScan(int requestId,String source) {
        if (!ready) { done(requestId,"unavailable","environment_unavailable"); if(configured)checkEnvironment(); return; }
        if (activeCheckout!=null || activeScan!=null) { if(requestId!=0)done(requestId,"busy","operation_in_progress"); return; }
        OwnedScan scan=new OwnedScan(requestId,source); activeScan=scan;
        ui.postDelayed(() -> finishScan(scan,"failed","restore_timeout"),NETWORK_TIMEOUT_MS);
        queryOwned(scan,0,"");
    }
    private void queryOwned(OwnedScan scan,int type,String continuation) {
        if (destroyed) return;
        if (type>1) { finishScan(scan,scan.failed?"failed":"restored",scan.failed?"receipt_verification_failed":""); return; }
        if (++scan.pageCount>200 || !scan.pages.add(type+":"+continuation)) { scan.failed=true; finishScan(scan,"failed","invalid_pagination"); return; }
        OwnedPurchasesReq req=new OwnedPurchasesReq(); req.setPriceType(type);
        if (!empty(continuation)) req.setContinuationToken(continuation);
        try {
            client.obtainOwnedPurchases(req).addOnSuccessListener(result -> ui.post(() -> {
                if (result.getReturnCode()!=0) { finishScan(scan,"failed","huawei_"+result.getReturnCode()); return; }
                processOwned(scan,type,result.getInAppPurchaseDataList(),result.getInAppSignature(),result.getSignatureAlgorithm());
                // Placed orders can be pending. Authenticate them, but never deliver state != PURCHASED.
                processOwned(scan,type,result.getPlacedInappPurchaseDataList(),result.getPlacedInappSignatureList(),result.getSignatureAlgorithm());
                String next=result.getContinuationToken();
                queryOwned(scan,empty(next)?type+1:type,empty(next)?"":next);
            })).addOnFailureListener(e -> ui.post(() -> finishScan(scan,"failed",error(e))));
        } catch (Exception e) { finishScan(scan,"failed",error(e)); }
    }
    private void processOwned(OwnedScan scan,int type,List<String> data,List<String> signatures,String algorithm) {
        if ((data==null || data.isEmpty()) && (signatures==null || signatures.isEmpty())) return;
        if (data==null || signatures==null || data.size()!=signatures.size()) { scan.failed=true; return; }
        for(int i=0;i<data.size();i++) {
            try { verifyAndDeliver(data.get(i),signatures.get(i),algorithm,scan.finished?"recovery":scan.source,scan.requestId,null,scan); }
            catch(Exception ignored) { scan.failed=true; }
        }
    }
    private void finishScan(OwnedScan scan,String status,String error) {
        if(scan.finished)return;
        scan.finished=true; if(activeScan==scan)activeScan=null;
        done(scan.requestId,status,error);
    }

    /** Return purchase state; only an authenticated PURCHASED order emits delivery. */
    private int verifyAndDeliver(String raw,String signature,String algorithm,String source,int requestId,Checkout checkout,OwnedScan scan) throws Exception {
        if(empty(signature) || !ReceiptVerifier.verify(raw,Base64.decode(signature,Base64.DEFAULT),publicKey,algorithm)) throw new SecurityException();
        JSONObject data=new JSONObject(raw);
        String storeId=data.getString("productId"); Product p=byStoreId.get(storeId);
        if(p==null) { if(checkout!=null)throw new SecurityException(); return -1; } // Retired, unconfigured product: no grant.
        if(!ReceiptVerifier.identityMatches(data.getString("applicationId"),data.getString("packageName"),storeId,data.getInt("kind"),appId,packageName,p.storeId,p.type))throw new SecurityException();
        String token=data.getString("purchaseToken"), order=data.getString("orderId");
        if(empty(token)||empty(order))throw new SecurityException();
        int state=data.getInt("purchaseState");
        if(checkout!=null && (!checkout.product.id.equals(p.id) || !checkout.payload.equals(data.getString("developerPayload"))
                || !ReceiptVerifier.priceMatches(data.getLong("price"),data.getString("currency"),checkout.price.getMicrosPrice(),checkout.price.getCurrency())))throw new SecurityException();
        if(state==3)return state;
        if(state!=0)throw new SecurityException();
        if(p.type==0 && data.getInt("consumptionState")!=0)throw new SecurityException();
        if(scan!=null && !scan.receipts.add(token))return state;
        Verified verified=new Verified(p,token,order);
        Verified old=verifiedTokens.get(token);
        if(old!=null && (!old.order.equals(order)||!old.product.id.equals(p.id)))throw new SecurityException();
        verifiedTokens.put(token,verified);
        signal("purchase_verified",new JSONObject().put("id",p.id).put("token",token).put("order_id",order)
                .put("type",p.type).put("source",source).put("request_id",requestId).toString());
        return state;
    }

    @UsedByGodot public void confirm_delivery(String token) {
        ui.post(() -> {
            Verified receipt=verifiedTokens.get(token);
            if(receipt==null) { signal("consumed",token,false,"unknown_verified_token"); return; }
            if(receipt.product.type!=0) { signal("consumed",token,true,""); return; }
            if(!consuming.add(token))return;
            ui.postDelayed(() -> { if(consuming.remove(token))signal("consumed",token,false,"consume_timeout"); },NETWORK_TIMEOUT_MS);
            ConsumeOwnedPurchaseReq req=new ConsumeOwnedPurchaseReq(); req.setPurchaseToken(token);
            try {
                client.consumeOwnedPurchase(req).addOnSuccessListener(result -> ui.post(() -> {
                    consuming.remove(token);
                    try {
                        if(result.getReturnCode()!=0 || !ReceiptVerifier.verify(result.getConsumePurchaseData(),Base64.decode(result.getDataSignature(),Base64.DEFAULT),publicKey,result.getSignatureAlgorithm()))throw new SecurityException();
                        JSONObject data=new JSONObject(result.getConsumePurchaseData());
                        if(!token.equals(data.getString("purchaseToken")) || !receipt.product.storeId.equals(data.getString("productId"))
                                || !appId.equals(data.getString("applicationId")) || !packageName.equals(data.getString("packageName"))
                                || data.getInt("consumptionState")!=1)throw new SecurityException();
                        verifiedTokens.remove(token); signal("consumed",token,true,"");
                    } catch(Exception ignored) { signal("consumed",token,false,"consume_verification_failed"); }
                })).addOnFailureListener(e -> ui.post(() -> {
                    consuming.remove(token);
                    if(errorCode(e)==OrderStatusCode.ORDER_PRODUCT_CONSUMED) { verifiedTokens.remove(token); signal("consumed",token,true,""); }
                    else signal("consumed",token,false,error(e));
                }));
            } catch(Exception e) { consuming.remove(token); signal("consumed",token,false,error(e)); }
        });
    }

    @Override public void onMainResume() {
        ui.postDelayed(() -> { if(configured && ready && activeCheckout==null && activeScan==null && !destroyed)beginScan(0,"recovery"); },1000);
    }
    @Override public void onMainDestroy() { destroyed=true; ui.removeCallbacksAndMessages(null); }
}
