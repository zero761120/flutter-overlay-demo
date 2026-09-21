package slayer.accessibility.service.flutter_accessibility_service;

import static slayer.accessibility.service.flutter_accessibility_service.Constants.*;
import static slayer.accessibility.service.flutter_accessibility_service.FlutterAccessibilityServicePlugin.CACHED_TAG;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.annotation.TargetApi;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.LruCache;
import android.view.Gravity;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import androidx.annotation.RequiresApi;


import com.google.gson.Gson;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.Objects;
import java.util.stream.Collectors;

import io.flutter.plugin.common.MethodChannel;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;


public class AccessibilityListener extends AccessibilityService {
    private static AccessibilityListener instance;

    /// LOCAL PATCH: payload queue. The broadcast stays a bare signal and the captured content
    /// never leaves the process.
    ///
    /// Upstream left the payload in one shared-prefs slot, so back-to-back events overwrote each
    /// other before the receiver read them. Putting it on the Intent instead fixed that race but
    /// created a much worse problem: sendBroadcast carries no receiverPermission and the action is
    /// a plain string, so any app on the device could register a receiver and passively read every
    /// other app's on-screen text. Both engines live in the same process, so an in-process queue
    /// fixes the race while exposing nothing — and it is not subject to Binder size limits either.
    /// Bounded on purpose: events are enqueued unconditionally, but only drained while something
    /// on the Dart side is listening. Unbounded, an idle app would grow this forever — the shared
    /// slot it replaced was at least self-limiting. Dropping the oldest keeps the newest events,
    /// which are the ones a live listener is about to want.
    static final java.util.concurrent.ConcurrentLinkedQueue<String> PAYLOADS =
            new java.util.concurrent.ConcurrentLinkedQueue<>();
    private static final int MAX_PENDING_PAYLOADS = 64;

    private static void enqueuePayload(String json) {
        PAYLOADS.add(json);
        while (PAYLOADS.size() > MAX_PENDING_PAYLOADS) {
            PAYLOADS.poll();
        }
    }

    /// LOCAL PATCH: "enabled in settings" and "actually bound" are different things — the
    /// service can be listed as enabled while onServiceConnected never completed. Callers
    /// need to tell those apart, otherwise a failed action looks like a successful one.
    static boolean isConnected() {
        return instance != null;
    }
    private static WindowManager mWindowManager;
    private static FlutterView mOverlayView;
    static private boolean isOverlayShown = false;
    private static final int CACHE_SIZE = 4 * 1024 * 1024; // 4Mib
    private static final int maxDepth = 20;
    private static LruCache<String, AccessibilityNodeInfo> nodeMap =
            new LruCache<>(CACHE_SIZE);
    // LOCAL PATCH: 15 truncates real layouts — measured "Maximum tree depth reached: 15"
    // on an ordinary list screen, which silently drops the leaf nodes that carry the text.
    private static final int DEFAULT_MAX_TREE_DEPTH = 60;
    private int maximumTreeDepth = DEFAULT_MAX_TREE_DEPTH;
    private static final int MAX_TREE_NODES = 800;

    public static AccessibilityNodeInfo getNodeInfo(String id) {
        return nodeMap.get(id);
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    @Override
    public void onAccessibilityEvent(AccessibilityEvent accessibilityEvent) {
        try {
            final int eventType = accessibilityEvent.getEventType();
            AccessibilityNodeInfo parentNodeInfo = accessibilityEvent.getSource();
            AccessibilityWindowInfo windowInfo = null;
            List<String> nextTexts = new ArrayList<>();
            List<Integer> actions = new ArrayList<>();
            List<HashMap<String, Object>> subNodeActions = new ArrayList<>();
            HashSet<AccessibilityNodeInfo> traversedNodes = new HashSet<>();
            HashMap<String, Object> data = new HashMap<>();
            if (parentNodeInfo == null) {
                // LOCAL PATCH: upstream dropped every event whose getSource() is null, which in
                // practice discards almost all TYPE_VIEW_CLICKED — measured on Android 15, clicks
                // consistently arrive with source=null. That is precisely the event anything
                // recording a user flow needs. The AccessibilityEvent itself still carries
                // packageName, className and getText() (for a click, usually the tapped label),
                // so emit that much instead of throwing the event away.
                HashMap<String, Object> minimal = new HashMap<>();
                minimal.put("eventType", eventType);
                // LOCAL PATCH: not String.valueOf — that turns a null into the literal "null",
                // the same anti-pattern fixed for capturedText/contentDescription below. A caller
                // filtering on `packageName == null` would never match the fake one.
                minimal.put("packageName", accessibilityEvent.getPackageName() == null ? null
                        : accessibilityEvent.getPackageName().toString());
                minimal.put("className", accessibilityEvent.getClassName() == null ? null
                        : accessibilityEvent.getClassName().toString());
                minimal.put("eventTime", accessibilityEvent.getEventTime());
                List<String> evtTexts = new ArrayList<>();
                // LOCAL PATCH: this is the path that now carries click and text-changed events,
                // so it is the most likely one to see a password field — guard it like the rest.
                if (!accessibilityEvent.isPassword()) {
                    for (CharSequence cs : accessibilityEvent.getText()) {
                        if (cs != null && cs.length() > 0) evtTexts.add(cs.toString());
                    }
                }
                minimal.put("nodesText", evtTexts);
                enqueuePayload(storeToSharedPrefs(minimal));
                Intent minimalIntent = new Intent(ACCESSIBILITY_INTENT);
                minimalIntent.putExtra(SEND_BROADCAST, true);
                sendBroadcast(minimalIntent);
                return;
            }
            String nodeId = generateNodeId(parentNodeInfo);
            String packageName = parentNodeInfo.getPackageName().toString();
            storeNode(nodeId, parentNodeInfo);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                windowInfo = parentNodeInfo.getWindow();
            }


            Intent intent = new Intent(ACCESSIBILITY_INTENT);

            data.put("mapId", nodeId);
            data.put("packageName", packageName);
            data.put("eventType", eventType);
            data.put("actionType", accessibilityEvent.getAction());
            data.put("eventTime", accessibilityEvent.getEventTime());
            data.put("movementGranularity", accessibilityEvent.getMovementGranularity());
            Rect rect = new Rect();
            parentNodeInfo.getBoundsInScreen(rect);
            data.put("screenBounds", getBoundingPoints(rect));
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                data.put("contentChangeTypes", accessibilityEvent.getContentChangeTypes());
            }
            // LOCAL PATCH: see getSubNodes — the parent node needs contentDescription too, and
            // both of these need the same isPassword guard as everything else.
            if (!parentNodeInfo.isPassword()
                    && parentNodeInfo.getContentDescription() != null) {
                data.put("contentDescription",
                        parentNodeInfo.getContentDescription().toString());
            }
            if (!parentNodeInfo.isPassword() && parentNodeInfo.getText() != null) {
                data.put("capturedText", parentNodeInfo.getText().toString());
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                data.put("nodeId", parentNodeInfo.getViewIdResourceName());
            }
            getSubNodes(parentNodeInfo, subNodeActions, traversedNodes, 0, nextTexts);
            data.put("nodesText", nextTexts);
            actions.addAll(parentNodeInfo.getActionList().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList()));
            data.put("parentActions", actions);
            data.put("subNodesActions", subNodeActions);
            data.put("isClickable", parentNodeInfo.isClickable());
            data.put("isScrollable", parentNodeInfo.isScrollable());
            data.put("isFocusable", parentNodeInfo.isFocusable());
            data.put("isCheckable", parentNodeInfo.isCheckable());
            data.put("isLongClickable", parentNodeInfo.isLongClickable());
            data.put("isEditable", parentNodeInfo.isEditable());
            if (windowInfo != null) {
                data.put("isActive", windowInfo.isActive());
                data.put("isFocused", windowInfo.isFocused());
                data.put("windowType", windowInfo.getType());
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    data.put("isPip", windowInfo.isInPictureInPictureMode());
                }
            }
            enqueuePayload(storeToSharedPrefs(data));
            intent.putExtra(SEND_BROADCAST, true);
            sendBroadcast(intent);
        } catch (Exception ex) {
            Log.e("EVENT", "onAccessibilityEvent: " + ex.getMessage());
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        boolean globalAction = intent.getBooleanExtra(INTENT_GLOBAL_ACTION, false);
        boolean systemActions = intent.getBooleanExtra(INTENT_SYSTEM_GLOBAL_ACTIONS, false);
        if (systemActions && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            List<Integer> actions = getSystemActions().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList());
            Intent broadcastIntent = new Intent(BROD_SYSTEM_GLOBAL_ACTIONS);
            broadcastIntent.putIntegerArrayListExtra("actions", new ArrayList<>(actions));
            sendBroadcast(broadcastIntent);
        }
        if (globalAction) {
            int actionId = intent.getIntExtra(INTENT_GLOBAL_ACTION_ID, 8);
            performGlobalAction(actionId);
        }
        Log.d("CMD_STARTED", "onStartCommand: " + startId);
        return START_STICKY;
    }


    @RequiresApi(api = Build.VERSION_CODES.N)
    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    void getSubNodes(AccessibilityNodeInfo node, List<HashMap<String, Object>> arr, HashSet<AccessibilityNodeInfo> traversedNodes, int currentDepth, List<String> texts) {
        // LOCAL PATCH: bound total nodes, not just depth. A wide list produces thousands of
        // siblings at shallow depth, and this whole traversal runs synchronously on the main
        // thread inside onAccessibilityEvent — being slow here makes the system drop the events
        // that follow, which is exactly the click we are trying to observe.
        if (arr.size() >= MAX_TREE_NODES) return;
        if (currentDepth >= maximumTreeDepth || node == null) {
            if (currentDepth >= maximumTreeDepth) {
                Log.d("TREE_DEPTH", "Maximum tree depth reached: " + currentDepth);
            }
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            if (traversedNodes.contains(node)) return;
            traversedNodes.add(node);
            String mapId = generateNodeId(node);
            AccessibilityWindowInfo windowInfo = null;
            HashMap<String, Object> nested = new HashMap<>();
            Rect rect = new Rect();
            node.getBoundsInScreen(rect);
            windowInfo = node.getWindow();
            nested.put("mapId", mapId);
            nested.put("nodeId", node.getViewIdResourceName());
            // LOCAL PATCH: upstream put the raw CharSequence here. Over the channel a null
            // CharSequence stringifies to the literal "null", so every text-less node came
            // back as the four-character string "null" instead of an absent value.
            // The isPassword() guard is part of the same patch: Android already tells us which
            // nodes hold secrets, so capturing them would be a gratuitous leak.
            nested.put("capturedText",
                    (node.isPassword() || node.getText() == null) ? null
                            : node.getText().toString());
            // LOCAL PATCH: upstream never sent contentDescription. Icon-only buttons usually
            // have no text at all, so without this they are indistinguishable from blank nodes.
            nested.put("contentDescription",
                    (node.isPassword() || node.getContentDescription() == null) ? null
                            : node.getContentDescription().toString());
            nested.put("screenBounds", getBoundingPoints(rect));
            nested.put("isClickable", node.isClickable());
            nested.put("isScrollable", node.isScrollable());
            nested.put("isFocusable", node.isFocusable());
            nested.put("isCheckable", node.isCheckable());
            nested.put("isLongClickable", node.isLongClickable());
            nested.put("isEditable", node.isEditable());
            nested.put("parentActions", node.getActionList().stream().map(AccessibilityNodeInfo.AccessibilityAction::getId).collect(Collectors.toList()));
            if (windowInfo != null) {
                nested.put("isActive", node.getWindow().isActive());
                nested.put("isFocused", node.getWindow().isFocused());
                nested.put("windowType", node.getWindow().getType());
            }
            // LOCAL PATCH: upstream declared nextTexts and shipped it as "nodesText" but never
            // put anything in it — the field was dead on arrival. Collect the visible strings
            // here; for scraping this is the single most useful thing the tree carries.
            if (!node.isPassword() && node.getText() != null && node.getText().length() > 0) {
                texts.add(node.getText().toString());
            }
            if (!node.isPassword()
                    && node.getContentDescription() != null
                    && node.getContentDescription().length() > 0) {
                texts.add(node.getContentDescription().toString());
            }
            arr.add(nested);
            storeNode(mapId, node);
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child == null)
                    continue;
                getSubNodes(child, arr, traversedNodes, currentDepth + 1, texts);
            }
        }
    }

    private HashMap<String, Integer> getBoundingPoints(Rect rect) {
        HashMap<String, Integer> frame = new HashMap<>();
        frame.put("left", rect.left);
        frame.put("right", rect.right);
        frame.put("top", rect.top);
        frame.put("bottom", rect.bottom);
        frame.put("width", rect.width());
        frame.put("height", rect.height());
        return frame;
    }


    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP_MR1)
    @Override
    protected void onServiceConnected() {
        instance = this;
        mWindowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        // LOCAL PATCH: the cached engine is only created in onAttachedToActivity. When the
        // process is started *by* the accessibility binding (e.g. right after an install or
        // a reboot) the cache is empty, and the original Objects.requireNonNull threw an NPE
        // out of onServiceConnected -> process crash -> rebind -> crash loop. The service
        // then never connects, so instance stays null and dispatchGesture silently returns
        // false. The overlay view is optional; skip it when there is no engine.
        FlutterEngine cachedEngine = FlutterEngineCache.getInstance().get(CACHED_TAG);
        if (cachedEngine == null) {
            Log.w("AccessibilityListener", "no cached engine; overlay feature disabled");
            return;
        }
        mOverlayView = new FlutterView(getApplicationContext(), new FlutterTextureView(getApplicationContext()));
        mOverlayView.attachToFlutterEngine(cachedEngine);
        mOverlayView.setFitsSystemWindows(true);
        mOverlayView.setFocusable(true);
        mOverlayView.setFocusableInTouchMode(true);
        mOverlayView.setBackgroundColor(Color.TRANSPARENT);
    }

    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP_MR1)
    static public void showOverlay(int width, int height, int gravity, boolean clickableThrough) {
        if (!isOverlayShown) {
            WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
            lp.type = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY;
            lp.format = PixelFormat.TRANSLUCENT;
            lp.width = width;
            lp.height = height;
            if (!clickableThrough) {
                lp.flags |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
            } else {
                lp.flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
            }
            lp.gravity = gravity;
            mWindowManager.addView(mOverlayView, lp);
            isOverlayShown = true;
        }
    }

    static public void removeOverlay() {
        if (isOverlayShown) {
            mWindowManager.removeView(mOverlayView);
            isOverlayShown = false;
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        removeOverlay();
        SharedPreferences sharedPreferences = getSharedPreferences(SHARED_PREFS_TAG, MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedPreferences.edit();
        editor.remove(ACCESSIBILITY_NODE).apply();
    }

    @Override
    public void onInterrupt() {
    }

    @SuppressWarnings("unchecked")
    @RequiresApi(api = Build.VERSION_CODES.N)
    public static void performDispatchGesture(List<Object> strokes, MethodChannel.Result result) {
        if (instance == null) {
            result.success(false);
            return;
        }
        try {
            GestureDescription.Builder gestureBuilder = new GestureDescription.Builder();
            for (Object strokeObj : strokes) {
                Map<String, Object> stroke = (Map<String, Object>) strokeObj;
                List<Object> pointObjs = (List<Object>) stroke.get("path");
                int startTime = ((Number) stroke.get("startTime")).intValue();
                int duration = ((Number) stroke.get("duration")).intValue();

                Path path = new Path();
                if (pointObjs != null && !pointObjs.isEmpty()) {
                    Map<String, Object> first = (Map<String, Object>) pointObjs.get(0);
                    path.moveTo(((Number) first.get("x")).floatValue(), ((Number) first.get("y")).floatValue());
                    for (int i = 1; i < pointObjs.size(); i++) {
                        Map<String, Object> pt = (Map<String, Object>) pointObjs.get(i);
                        path.lineTo(((Number) pt.get("x")).floatValue(), ((Number) pt.get("y")).floatValue());
                    }
                }
                gestureBuilder.addStroke(new GestureDescription.StrokeDescription(path, startTime, duration));
            }

            instance.dispatchGesture(gestureBuilder.build(), new AccessibilityService.GestureResultCallback() {
                @Override
                public void onCompleted(GestureDescription gestureDescription) {
                    new Handler(Looper.getMainLooper()).post(() -> result.success(true));
                }

                @Override
                public void onCancelled(GestureDescription gestureDescription) {
                    new Handler(Looper.getMainLooper()).post(() -> result.success(false));
                }
            }, null);
        } catch (Exception e) {
            Log.e("GESTURE", "performDispatchGesture: " + e.getMessage());
            result.success(false);
        }
    }


    private String generateNodeId(AccessibilityNodeInfo node) {
        return node.getWindowId() + "_" + node.getClassName() + "_" + node.getText() + "_" + node.getContentDescription(); //UUID.randomUUID().toString();
    }

    private void storeNode(String uuid, AccessibilityNodeInfo node) {
        if (node == null) {
            return;
        }
        nodeMap.put(uuid, node);
    }

    // LOCAL PATCH: returns the serialized payload so the caller can put it straight on the
    // Intent. Upstream used the broadcast purely as a signal and left the payload in this one
    // shared slot, so back-to-back events overwrote each other before the receiver read them —
    // silently lossy, and worst for exactly the bursty events (a click is immediately followed
    // by content-changed). The prefs write stays for anything else that reads it.
    String storeToSharedPrefs(HashMap<String, Object> data) {
        SharedPreferences sharedPreferences = getSharedPreferences(SHARED_PREFS_TAG, MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedPreferences.edit();
        Gson gson = new Gson();
        String json = gson.toJson(data);
        editor.putString(ACCESSIBILITY_NODE, json);
        editor.apply();
        return json;
    }

}
