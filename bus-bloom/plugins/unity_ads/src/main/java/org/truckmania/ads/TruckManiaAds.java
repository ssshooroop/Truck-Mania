package org.truckmania.ads;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.unity3d.ads.*;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.*;

/** SDK calls and all mutable native state stay on Android's UI thread. */
public final class TruckManiaAds extends GodotPlugin {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Map<String, RewardedAd> rewards = new HashMap<>();
    private final Map<String, Integer> loading = new HashMap<>();
    private InterstitialAd interstitial;
    private String interstitialId = "";
    private boolean initialized, initializing;
    private int sequence, activeRequest;
    public TruckManiaAds(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "TruckManiaAds"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
            new SignalInfo("initialized", Boolean.class, String.class),
            new SignalInfo("loaded", String.class, Boolean.class, String.class),
            new SignalInfo("finished", Integer.class, String.class, Boolean.class, String.class),
            new SignalInfo("started", Integer.class, String.class)
        ));
    }
    private void report(String event, Object... args) {
        Log.i("TruckManiaAds", event + " " + Arrays.toString(args));
        emitSignal(event, args);
    }
    private static String describe(UnityAdsError error) {
        return error == null ? "" : "sdk_" + error.getCode() + ": " + error.getMessage();
    }
    @UsedByGodot public void initialize(String gameId, boolean testMode) {
        ui.post(() -> {
            if (initialized) { report("initialized", true, ""); return; }
            if (initializing) return;
            initializing = true;
            // No consent is inferred from the store's age rating. Contextual only.
            UnityAds.setUserConsent(false);
            UnityAds.setUserOptOut(true);
            UnityAds.setNonBehavioral(true);
            try {
                UnityAds.initialize(new InitializationConfiguration.Builder(gameId)
                    .withTestMode(testMode).build(), error -> ui.post(() -> {
                    initializing = false;
                    initialized = error == null;
                    report("initialized", initialized, describe(error));
                }));
            } catch (Exception e) {
                initializing = false;
                report("initialized", false, e.toString());
            }
        });
    }
    @UsedByGodot public void load(String unit, boolean rewarded) {
        ui.post(() -> {
            if (!initialized || loading.containsKey(unit)) return;
            int ticket = ++sequence;
            loading.put(unit, ticket);
            ui.postDelayed(() -> {
                if (Objects.equals(loading.get(unit), ticket)) {
                    loading.remove(unit);
                    report("loaded", unit, false, "load_timeout");
                }
            }, 45000);
            LoadConfiguration config = new LoadConfiguration.Builder(unit).build();
            try {
                if (rewarded) RewardedAd.load(config, (ad, error) -> ui.post(() -> {
                    if (!Objects.equals(loading.get(unit), ticket)) return;
                    loading.remove(unit);
                    if (ad != null) {
                        rewards.put(unit, ad);
                        ad.setOnAdExpired(expired -> ui.post(() -> {
                            if (rewards.get(unit) == expired) {
                                rewards.remove(unit);
                                report("loaded", unit, false, "expired");
                            }
                        }));
                    }
                    report("loaded", unit, ad != null, describe(error));
                }));
                else InterstitialAd.load(config, (ad, error) -> ui.post(() -> {
                    if (!Objects.equals(loading.get(unit), ticket)) return;
                    loading.remove(unit);
                    interstitial = ad;
                    interstitialId = unit;
                    if (ad != null) ad.setOnAdExpired(expired -> ui.post(() -> {
                        if (interstitial == expired) {
                            interstitial = null;
                            report("loaded", unit, false, "expired");
                        }
                    }));
                    report("loaded", unit, ad != null, describe(error));
                }));
            } catch (Exception e) {
                loading.remove(unit);
                report("loaded", unit, false, e.toString());
            }
        });
    }
    private void finish(int request, String unit, boolean reward, String reason) {
        if (activeRequest != request) return;
        activeRequest = 0;
        report("finished", request, unit, reward, reason);
    }
    @UsedByGodot public void show(String unit, boolean rewarded, int request) {
        ui.post(() -> {
            if (activeRequest != 0 || getActivity() == null) {
                report("finished", request, unit, false, "unavailable"); return;
            }
            activeRequest = request;
            ShowConfiguration config = new ShowConfiguration.Builder().build();
            try {
                if (rewarded) {
                    RewardedAd ad = rewards.remove(unit);
                    if (ad == null) { finish(request, unit, false, "not_loaded"); return; }
                    ad.show(getActivity(), config, new RewardedShowListener() {
                        private boolean earned;
                        public void onRewarded(RewardedAd a) { ui.post(() -> earned = true); }
                        public void onStarted(RewardedAd a) { ui.post(() -> report("started", request, unit)); }
                        public void onClicked(RewardedAd a) {}
                        public void onCompleted(RewardedAd a, ShowFinishState state) {
                            ui.post(() -> finish(request, unit, earned, earned ? "rewarded" : "skipped"));
                        }
                        public void onFailed(RewardedAd a, UnityAdsError error) {
                            ui.post(() -> finish(request, unit, earned, describe(error)));
                        }
                    });
                } else {
                    InterstitialAd ad = interstitial;
                    if (ad == null || !unit.equals(interstitialId)) {
                        finish(request, unit, false, "not_loaded"); return;
                    }
                    interstitial = null;
                    ad.show(getActivity(), config, new InterstitialShowListener() {
                        public void onStarted(InterstitialAd a) { ui.post(() -> report("started", request, unit)); }
                        public void onClicked(InterstitialAd a) {}
                        public void onCompleted(InterstitialAd a, ShowFinishState state) {
                            ui.post(() -> finish(request, unit, false, "closed"));
                        }
                        public void onFailed(InterstitialAd a, UnityAdsError error) {
                            ui.post(() -> finish(request, unit, false, describe(error)));
                        }
                    });
                }
            } catch (Exception e) { finish(request, unit, false, e.toString()); }
        });
    }
}
