package flutter.overlay.window.flutter_overlay_window;

import android.animation.ValueAnimator;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.app.PendingIntent;
import android.graphics.Point;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Choreographer;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.animation.AccelerateInterpolator;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;
import io.flutter.plugin.common.MethodChannel;

public class OverlayService extends Service implements View.OnTouchListener {
    private final int DEFAULT_NAV_BAR_HEIGHT_DP = 48;
    private final int DEFAULT_STATUS_BAR_HEIGHT_DP = 25;

    private Integer mStatusBarHeight = -1;
    private Integer mNavigationBarHeight = -1;
    private Resources mResources;

    public static final String INTENT_EXTRA_IS_CLOSE_WINDOW = "IsCloseWindow";

    private static OverlayService instance;
    public static boolean isRunning = false;
    private WindowManager windowManager = null;
    private FlutterView flutterView;
    private MethodChannel flutterChannel;
    private BasicMessageChannel<Object> overlayMessageChannel;
    private int clickableFlag = WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;

    private Handler mAnimationHandler = new Handler();
    private float lastX, lastY;
    private int lastYPosition;
    private boolean dragging;
    private static final float MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER = 0.8f;
    private Point szWindow = new Point();
    private Timer mTrayAnimationTimer;
    private TrayAnimationTimerTask mTrayTimerTask;

    // LOCAL PATCH: drag-to-dismiss (see showDismissTarget).
    private static final int DISMISS_VIEW_DP = 88;
    private static final int DISMISS_RADIUS_DP = 28;
    private static final int DISMISS_CAPTURED_RADIUS_DP = 36;
    private static final int DISMISS_MAGNET_RADIUS_DP = 64;
    private static final int DISMISS_BOTTOM_MARGIN_DP = 72;
    /// The window currently is the ball. The ball and the solution card are both natively
    /// draggable, but only the ball gets the dismiss target and the snap to the edge; only the app
    /// knows which one is up, so it tells us via setBallMode.
    private boolean isBall = true;
    /// The app's "snap to edge" toggle (setSnapToEdge). The snap itself runs here on release.
    /// Static on purpose: every show creates a new OverlayService, while the app's toggle lives on
    /// in the cached overlay engine, and the app has no per-show signal to re-send it on — the
    /// overlay engine only ever receives appIsResumed, and LifecycleChannel.sendState drops a
    /// repeated state (read from the 3.38.10 embedding), so Dart sees "resumed" once per process.
    /// An instance field would fall back to true on every reopen with the panel still saying off.
    private static boolean snapToEdge = true;
    private DismissTargetView dismissView;
    /// The target is up for the current drag. Its window exists for as long as the ball's does
    /// (see addDismissTarget); this tracks visibility.
    private boolean dismissShown;
    /// The ball is stuck to the target and ignores the finger until it leaves the magnet.
    private boolean dismissCaptured;
    private int windowOffsetX, windowOffsetY;
    /// Squared platform touch slop, px² — distance before a touch on the window becomes a drag.
    private int touchSlopSquare = 25;
    // Motion constants from AOSP MagnetizedObject (android13-release). Its velocities are px/s;
    // converted to dp/s at this Sony's density (2.625) so they hold on other screens.
    /// SpringForce.STIFFNESS_MEDIUM / DAMPING_RATIO_NO_BOUNCY — the spring into the target.
    private static final float STICK_STIFFNESS = 1500f;
    private static final float STICK_DAMPING_RATIO = 1f;
    /// StackAnimationController.SPRING_TO_TOUCH_STIFFNESS / SPRING_AFTER_FLING_DAMPING_RATIO —
    /// the spring back to the finger after leaving the magnet. It starts from rest there.
    private static final float TOUCH_STIFFNESS = 12000f;
    private static final float TOUCH_DAMPING_RATIO = 0.85f;
    /// STACK_SPRING_STIFFNESS / SPRING_AFTER_FLING_DAMPING_RATIO — the spring to the edge on release.
    private static final float EDGE_STIFFNESS = 700f;
    private static final float EDGE_DAMPING_RATIO = 0.85f;
    /// ESCAPE_VELOCITY: 750 px/s — flung at least this fast towards the far edge, go there.
    private static final float ESCAPE_VELOCITY_DP = 286f;
    /// flingToTargetMinVelocity / flingUnstuckFromTargetMinVelocity: 4000 px/s.
    private static final float FLING_MIN_VELOCITY_DP = 1500f;
    /// stickToTargetMaxXVelocity: 2000 px/s — sweeping through sideways is not an intent to stick.
    private static final float STICK_MAX_X_VELOCITY_DP = 750f;
    private VelocityTracker velocityTracker;
    private float fingerX, fingerY;
    /// While true the spring loop, not the finger delta, places the ball's window.
    private boolean springing;
    private enum SpringTarget { FINGER, DISMISS_TARGET, EDGE }

    private SpringTarget springTarget;
    /// Ball centre at the edge it is snapping to.
    private float edgeX, edgeY;
    private float springStiffness;
    private float springDampingRatio;
    /// Ball centre on screen and its velocity, px and px/s.
    private float ballX, ballY, ballVx, ballVy;
    private long lastSpringFrameNanos;
    /// Released (or flung) into the target: dismiss once the spring settles there.
    private boolean dismissOnArrival;
    private boolean dismissing;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverLay", "Destroying the overlay window service");
        removeDismissTarget(); // LOCAL PATCH (drag-to-dismiss)
        if (windowManager != null) {
            windowManager.removeView(flutterView);
            windowManager = null;
            flutterView.detachFromFlutterEngine();
            flutterView = null;
        }
        isRunning = false;
        NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.cancel(OverlayConstants.NOTIFICATION_ID);
        instance = null;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // LOCAL PATCH: same defect as AccessibilityListener.onStartCommand — upstream returned
        // START_STICKY and dereferenced the intent unconditionally, so a process death while the
        // overlay was up meant a restart with a null intent and an NPE. A restart could not bring
        // the overlay back anyway (the position and size live in the intent that is gone), so all
        // returns are now NOT_STICKY; the null check covers a stale sticky record.
        if (intent == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        mResources = getApplicationContext().getResources();
        int startX = intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
        int startY = intent.getIntExtra("startY", OverlayConstants.DEFAULT_XY);
        boolean isCloseWindow = intent.getBooleanExtra(INTENT_EXTRA_IS_CLOSE_WINDOW, false);
        if (isCloseWindow) {
            removeDismissTarget(); // LOCAL PATCH (drag-to-dismiss)
            if (windowManager != null) {
                windowManager.removeView(flutterView);
                windowManager = null;
                flutterView.detachFromFlutterEngine();
                stopSelf();
            }
            isRunning = false;
            return START_NOT_STICKY;
        }
        if (windowManager != null) {
            windowManager.removeView(flutterView);
            windowManager = null;
            flutterView.detachFromFlutterEngine();
            stopSelf();
        }
        isRunning = true;
        Log.d("onStartCommand", "Service started");
        FlutterEngine engine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);
        engine.getLifecycleChannel().appIsResumed();
        flutterView = new FlutterView(getApplicationContext(), new FlutterTextureView(getApplicationContext()));
        flutterView.attachToFlutterEngine(FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG));
        flutterView.setFitsSystemWindows(true);
        flutterView.setFocusable(true);
        flutterView.setFocusableInTouchMode(true);
        flutterView.setBackgroundColor(Color.TRANSPARENT);
        flutterChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("updateFlag")) {
                String flag = call.argument("flag").toString();
                updateOverlayFlag(result, flag);
            } else if (call.method.equals("updateOverlayPosition")) {
                int x = call.<Integer>argument("x");
                int y = call.<Integer>argument("y");
                moveOverlay(x, y, result);
            } else if (call.method.equals("resizeOverlay")) {
                int width = call.argument("width");
                int height = call.argument("height");
                boolean enableDrag = call.argument("enableDrag");
                resizeOverlay(width, height, enableDrag, result);
            } else if (call.method.equals("getScreenSize")) {
                result.success(currentScreenSizePx());
            } else if (call.method.equals("setBallMode")) {
                // LOCAL PATCH (drag-to-dismiss / edge snap): the three methods below.
                isBall = Boolean.TRUE.equals(call.argument("ball"));
                if (!isBall) {
                    // The app is about to move / resize the window itself.
                    springing = false;
                    hideDismissTarget(false);
                }
                result.success(null);
            } else if (call.method.equals("setSnapToEdge")) {
                snapToEdge = Boolean.TRUE.equals(call.argument("enabled"));
                result.success(null);
            } else if (call.method.equals("exitApp")) {
                result.success(null);
                exitApp();
            }
        });
        overlayMessageChannel.setMessageHandler((message, reply) -> {
            WindowSetup.messenger.send(message);
        });
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            windowManager.getDefaultDisplay().getSize(szWindow);
        } else {
            DisplayMetrics displaymetrics = new DisplayMetrics();
            windowManager.getDefaultDisplay().getMetrics(displaymetrics);
            int w = displaymetrics.widthPixels;
            int h = displaymetrics.heightPixels;
            szWindow.set(w, h);
        }
        int dx = startX == OverlayConstants.DEFAULT_XY ? 0 : startX;
        int dy = startY == OverlayConstants.DEFAULT_XY ? -statusBarHeightPx() : startY;
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowSetup.width == -1999 ? -1 : WindowSetup.width,
                WindowSetup.height != -1999 ? WindowSetup.height : screenHeight(),
                0,
                -statusBarHeightPx(),
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE,
                WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
                        | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
        );
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
            params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
        }
        params.gravity = WindowSetup.gravity;
        flutterView.setOnTouchListener(this);
        // LOCAL PATCH (drag-to-dismiss): the target goes in before the ball — same-type windows
        // stack in the order they are added.
        removeDismissTarget();
        addDismissTarget();
        windowManager.addView(flutterView, params);
        moveOverlay(dx, dy, null);
        // LOCAL PATCH (drag-to-dismiss / edge snap): the overlay always (re)appears as the ball;
        // the app flips this off whenever it leaves that state.
        isBall = true;
        dismissing = false;
        return START_NOT_STICKY;
    }


    // LOCAL PATCH: the overlay window is not an Activity, so nothing repositions it when the
    // display rotates — it keeps its old x/y and can end up completely off-screen (measured:
    // y=2084 while the landscape viewport is only 1033 tall, leaving the ball unreachable).
    // Dart's didChangeMetrics is not a usable hook here: the ball's own window is a fixed
    // 48dp and its viewport metrics do not change on rotation, so the callback never fires.
    // A Service does reliably receive onConfigurationChanged, so clamp here.
    /// MATCH_PARENT / FILL_PARENT 是負值，不是尺寸；把它們解讀成整個螢幕那一軸的長度。
    private static int sizeOf(int paramSize, int screenSize, int measured) {
        if (paramSize == WindowManager.LayoutParams.MATCH_PARENT) return screenSize;
        return paramSize > 0 ? paramSize : measured;
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (windowManager == null || flutterView == null) return;
        // LOCAL PATCH (drag-to-dismiss / edge snap): a snap in flight aims at an edge of the old
        // screen width, and the next spring frame would overwrite the clamp below with it — the
        // ball settles off-screen. Stop it here and re-aim it once the window is clamped.
        boolean wasSnapping = springing && springTarget == SpringTarget.EDGE;
        if (wasSnapping) springing = false;
        windowManager.getDefaultDisplay().getSize(szWindow);
        WindowManager.LayoutParams params =
                (WindowManager.LayoutParams) flutterView.getLayoutParams();
        // 用 params 的尺寸而非 flutterView.getWidth()/getHeight()：後者是即時量測值，若 config
        // change 剛好落在 resizeOverlay 之後、layout 追上之前，會量到舊值或 0，上界就算錯了。
        // MATCH_PARENT（-1）要當成「滿版」而不是退回量測值——面板展開時 width 正是 -1，
        // 退回去就等於這個修正在最常互動的狀態下悄悄失效。
        int w = sizeOf(params.width, szWindow.x, flutterView.getWidth());
        int h = sizeOf(params.height, szWindow.y, flutterView.getHeight());
        int maxX = Math.max(0, szWindow.x - w);
        int maxY = Math.max(0, szWindow.y - h);
        int clampedX = Math.min(Math.max(params.x, 0), maxX);
        int clampedY = Math.min(Math.max(params.y, 0), maxY);
        if (clampedX != params.x || clampedY != params.y) {
            params.x = clampedX;
            params.y = clampedY;
            windowManager.updateViewLayout(flutterView, params);
        }
        // With the live velocity, not 0: a ball flung past the escape velocity towards the far
        // edge would otherwise be turned back to the near one.
        if (wasSnapping) springToEdge(ballVx);
    }

    // LOCAL PATCH: the overlay engine's `Display.size` is frozen at the orientation it was created
    // in. The embedding only pushes display metrics when it can find an Activity
    // (ViewUtils.calculateMaximumDisplayMetrics returns early otherwise — read from the
    // disassembled embedding of Flutter 3.38.10 / engine cafcda5721), and this engine lives
    // under a Service. Measured: engine created in landscape, rotated back to portrait, Dart still
    // saw 975dp wide, so "snap right past half the width" could never trigger. Dart asks here
    // instead. Real metrics (full display incl. system bars) to match what Display.size meant.
    // A fresh WindowManager rather than the field: the field is null after closeOverlay, while the
    // cached engine — and its Dart code — keeps running.
    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    private Map<String, Integer> currentScreenSizePx() {
        WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        DisplayMetrics dm = new DisplayMetrics();
        wm.getDefaultDisplay().getRealMetrics(dm);
        Map<String, Integer> size = new HashMap<>();
        size.put("width", dm.widthPixels);
        size.put("height", dm.heightPixels);
        return size;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    private int screenHeight() {
        Display display = windowManager.getDefaultDisplay();
        DisplayMetrics dm = new DisplayMetrics();
        display.getRealMetrics(dm);
        return inPortrait() ?
                dm.heightPixels + statusBarHeightPx() + navigationBarHeightPx()
                :
                dm.heightPixels + statusBarHeightPx();
    }

    private int statusBarHeightPx() {
        if (mStatusBarHeight == -1) {
            int statusBarHeightId = mResources.getIdentifier("status_bar_height", "dimen", "android");

            if (statusBarHeightId > 0) {
                mStatusBarHeight = mResources.getDimensionPixelSize(statusBarHeightId);
            } else {
                mStatusBarHeight = dpToPx(DEFAULT_STATUS_BAR_HEIGHT_DP);
            }
        }

        return mStatusBarHeight;
    }

    int navigationBarHeightPx() {
        if (mNavigationBarHeight == -1) {
            int navBarHeightId = mResources.getIdentifier("navigation_bar_height", "dimen", "android");

            if (navBarHeightId > 0) {
                mNavigationBarHeight = mResources.getDimensionPixelSize(navBarHeightId);
            } else {
                mNavigationBarHeight = dpToPx(DEFAULT_NAV_BAR_HEIGHT_DP);
            }
        }

        return mNavigationBarHeight;
    }


    private void updateOverlayFlag(MethodChannel.Result result, String flag) {
        if (windowManager != null) {
            WindowSetup.setFlag(flag);
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.flags = WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS |
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
                params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
            } else {
                params.alpha = 1;
            }
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void resizeOverlay(int width, int height, boolean enableDrag, MethodChannel.Result result) {
        if (windowManager != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.width = (width == -1999 || width == -1) ? -1 : dpToPx(width);
            params.height = (height != 1999 || height != -1) ? dpToPx(height) : height;
            WindowSetup.enableDrag = enableDrag;
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void moveOverlay(int x, int y, MethodChannel.Result result) {
        if (windowManager != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.x = (x == -1999 || x == -1) ? -1 : dpToPx(x);
            params.y = dpToPx(y);
            windowManager.updateViewLayout(flutterView, params);
            if (result != null)
                result.success(true);
        } else {
            if (result != null)
                result.success(false);
        }
    }


    public static Map<String, Double> getCurrentPosition() {
        if (instance != null && instance.flutterView != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
            Map<String, Double> position = new HashMap<>();
            position.put("x", instance.pxToDp(params.x));
            position.put("y", instance.pxToDp(params.y));
            return position;
        }
        return null;
    }

    public static boolean moveOverlay(int x, int y) {
        if (instance != null && instance.flutterView != null) {
            if (instance.windowManager != null) {
                WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
                params.x = (x == -1999 || x == -1) ? -1 : instance.dpToPx(x);
                params.y = instance.dpToPx(y);
                instance.windowManager.updateViewLayout(instance.flutterView, params);
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }


    @Override
    public void onCreate() {
        // LOCAL PATCH: see the drag start in onTouch.
        int touchSlop = ViewConfiguration.get(this).getScaledTouchSlop();
        touchSlopSquare = touchSlop * touchSlop;
        // Get the cached FlutterEngine
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);

        if (flutterEngine == null) {
            // Handle the error if engine is not found
            Log.e("OverlayService", "Flutter engine not found, hence creating new flutter engine");
            FlutterEngineGroup engineGroup = new FlutterEngineGroup(this);
            DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "overlayMain"
            );  // "overlayMain" is custom entry point

            flutterEngine = engineGroup.createAndRunEngine(this, entryPoint);

            // Cache the created FlutterEngine for future use
            FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, flutterEngine);
        }

        // Create the MethodChannel with the properly initialized FlutterEngine
        if (flutterEngine != null) {
            flutterChannel = new MethodChannel(flutterEngine.getDartExecutor(), OverlayConstants.OVERLAY_TAG);
            overlayMessageChannel = new BasicMessageChannel(flutterEngine.getDartExecutor(), OverlayConstants.MESSENGER_TAG, JSONMessageCodec.INSTANCE);
        }

        createNotificationChannel();
        Intent notificationIntent = new Intent(this, FlutterOverlayWindowPlugin.class);
        int pendingFlags;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            pendingFlags = PendingIntent.FLAG_IMMUTABLE;
        } else {
            pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(this,
                0, notificationIntent, pendingFlags);
        final int notifyIcon = getDrawableResourceId("mipmap", "launcher");
        Notification notification = new NotificationCompat.Builder(this, OverlayConstants.CHANNEL_ID)
                .setContentTitle(WindowSetup.overlayTitle)
                .setContentText(WindowSetup.overlayContent)
                .setSmallIcon(notifyIcon == 0 ? R.drawable.notification_icon : notifyIcon)
                .setContentIntent(pendingIntent)
                .setVisibility(WindowSetup.notificationVisibility)
                .build();
        startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        instance = this;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    OverlayConstants.CHANNEL_ID,
                    "Foreground Service Channel",
                    NotificationManager.IMPORTANCE_DEFAULT
            );
            NotificationManager manager = getSystemService(NotificationManager.class);
            assert manager != null;
            manager.createNotificationChannel(serviceChannel);
        }
    }

    private int getDrawableResourceId(String resType, String name) {
        return getApplicationContext().getResources().getIdentifier(String.format("ic_%s", name), resType, getApplicationContext().getPackageName());
    }

    private int dpToPx(int dp) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                Float.parseFloat(dp + ""), mResources.getDisplayMetrics());
    }

    private double pxToDp(int px) {
        return (double) px / mResources.getDisplayMetrics().density;
    }

    private boolean inPortrait() {
        return mResources.getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;
    }

    @Override
    public boolean onTouch(View view, MotionEvent event) {
        // LOCAL PATCH (drag-to-dismiss / edge snap): this method's velocity tracking, target, magnet,
        // release and snap handling. The ball is shrinking into the target and the app is about to
        // go away.
        if (dismissing) return true;
        if (windowManager != null && WindowSetup.enableDrag) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    dragging = false;
                    // LOCAL PATCH (drag-to-dismiss): a new touch takes the ball back, as AOSP's
                    // MagnetizedObject does on ACTION_DOWN. A pending "dismiss once the spring
                    // lands" must be called off with the spring — left set, the next spring to
                    // settle (e.g. back to the finger after dragging out) dismissed the app — and
                    // the target and capture state start over.
                    boolean wasSpringing = springing;
                    springing = false;
                    dismissOnArrival = false;
                    hideDismissTarget(false);
                    lastX = event.getRawX();
                    lastY = event.getRawY();
                    recycleVelocityTracker();
                    trackVelocity(event);
                    // loc - params is the fixed offset between LayoutParams and screen coordinates
                    // — a property of the window, not of where it is. Measured only while the
                    // window stands still: mid-spring, getLocationOnScreen still reports the
                    // previous frame, so keep the offset from the last measurement then.
                    if (!wasSpringing) {
                        int[] loc = new int[2];
                        flutterView.getLocationOnScreen(loc);
                        windowOffsetX = loc[0] - params.x;
                        windowOffsetY = loc[1] - params.y;
                    }
                    break;
                case MotionEvent.ACTION_MOVE:
                    trackVelocity(event);
                    float dx = event.getRawX() - lastX;
                    float dy = event.getRawY() - lastY;
                    // LOCAL PATCH: upstream started the drag after 5 physical px (~2dp). Once a drag
                    // ends in a cancel for Flutter (endDragForFlutter), that made a tap that wobbled
                    // a couple of dp do nothing at all — before, Flutter's own tap slop still let it
                    // through. Flutter takes that slop from getScaledTouchSlop() too, so starting
                    // the drag there puts both sides on one boundary: under it a tap for both, past
                    // it a drag for both (measured on the Sony: a 40px wobble opens the panel, 50px
                    // drags).
                    if (!dragging && dx * dx + dy * dy < touchSlopSquare) {
                        return false;
                    }
                    lastX = event.getRawX();
                    lastY = event.getRawY();
                    fingerX = lastX;
                    fingerY = lastY;
                    if (!dragging && isBall) showDismissTarget();
                    dragging = true;
                    if (updateMagnet() || springing) break;
                    boolean invertX = WindowSetup.gravity == (Gravity.TOP | Gravity.RIGHT)
                            || WindowSetup.gravity == (Gravity.CENTER | Gravity.RIGHT)
                            || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                    boolean invertY = WindowSetup.gravity == (Gravity.BOTTOM | Gravity.LEFT)
                            || WindowSetup.gravity == Gravity.BOTTOM
                            || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                    int xx = params.x + ((int) dx * (invertX ? -1 : 1));
                    int yy = params.y + ((int) dy * (invertY ? -1 : 1));
                    params.x = xx;
                    params.y = yy;
                    if (windowManager != null) {
                        windowManager.updateViewLayout(flutterView, params);
                    }
                    dragging = true;
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    trackVelocity(event);
                    velocityTracker.computeCurrentVelocity(1000);
                    float releaseVx = velocityTracker.getXVelocity();
                    float releaseVy = velocityTracker.getYVelocity();
                    recycleVelocityTracker();
                    if (event.getAction() == MotionEvent.ACTION_UP && dismissShown
                            && releaseDismisses(event.getRawX(), event.getRawY(), releaseVx, releaseVy)) {
                        return endDragForFlutter(event);
                    }
                    springing = false;
                    hideDismissTarget(true);
                    // On cancel too: a drag the system took over (edge back gesture) would
                    // otherwise leave the ball wherever it was.
                    if (dragging && isBall && snapToEdge) springToEdge(releaseVx);
                    lastYPosition = params.y;
                    if (!WindowSetup.positionGravity.equals("none")) {
                        if (windowManager == null) return false;
                        windowManager.updateViewLayout(flutterView, params);
                        mTrayTimerTask = new TrayAnimationTimerTask();
                        mTrayAnimationTimer = new Timer();
                        mTrayAnimationTimer.schedule(mTrayTimerTask, 0, 25);
                    }
                    return endDragForFlutter(event);
                default:
                    return false;
            }
            return false;
        }
        return false;
    }

    /// LOCAL PATCH: a drag must never end as a tap in Flutter. The window follows the finger, so
    /// in the window's own coordinates the pointer barely moves and Flutter's tap slop (on Android,
    /// the platform touch slop) is only exceeded on an event where the window happens to lag
    /// behind the finger. Measured with
    /// a slow drag inward from the left edge: Flutter saw at most 13 logical px of movement, fired
    /// onTap on release and the panel opened; the pre-patch build differed only in having one
    /// lagging event (26 px) in that drag — a race, not a rule. Whenever we dragged, Flutter gets a
    /// cancel instead of the up. A plain tap (never past the 5px drag slop) is left alone.
    private boolean endDragForFlutter(MotionEvent event) {
        if (!dragging || event.getAction() != MotionEvent.ACTION_UP) return false;
        MotionEvent cancel = MotionEvent.obtain(event);
        cancel.setAction(MotionEvent.ACTION_CANCEL);
        flutterView.onTouchEvent(cancel);
        cancel.recycle();
        return true;
    }

    // LOCAL PATCH: drag-to-dismiss, modelled on the platform's own bubbles (AOSP WM Shell
    // DismissView + MagnetizedObject): a target appears at the bottom once a drag starts. Inside
    // the magnet radius the ball springs onto it carrying the finger's velocity; leaving the
    // radius springs it back to the finger before plain dragging resumes; releasing while stuck —
    // or flinging fast towards it from anywhere — lands the ball in it and it shrinks away.
    // A first version teleported the window on stick / unstick and hid the ball instantly on
    // release; on the device that read as stutter with no trajectory, so all three now move.
    //
    // A separate native window rather than drawing it in Flutter: this plugin hosts exactly one
    // Flutter window, so drawing the target there means resizing the ball's window to full screen
    // mid-gesture — which is the ~280ms surface lag the app already works around, plus a jump in
    // the touch coordinates when the window origin moves under the finger.
    //
    // The ball must stack above the target — it slides onto it and sits there while stuck. A first
    // version added the target's window when the drag started, i.e. after the ball's, and on video
    // the ball visibly sank under the dark disc for the few frames it took to slide in. So the
    // target's window is added (transparent) right before the ball's and only faded in and out.
    private void addDismissTarget() {
        int size = dpToPx(DISMISS_VIEW_DP);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                size,
                size,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        // Top-left with absolute coordinates, same as the ball: a centred gravity is measured
        // against the parent frame minus the system bars, not the screen.
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        dismissView = new DismissTargetView(getApplicationContext(),
                dpToPx(DISMISS_RADIUS_DP), dpToPx(DISMISS_CAPTURED_RADIUS_DP), dpToPx(3));
        dismissView.setAlpha(0f);
        ((WindowManager) getSystemService(WINDOW_SERVICE)).addView(dismissView, lp);
    }

    private void removeDismissTarget() {
        dismissShown = false;
        dismissCaptured = false;
        if (dismissView == null) return;
        dismissView.animate().cancel();
        if (dismissView.isAttachedToWindow()) {
            ((WindowManager) getSystemService(WINDOW_SERVICE)).removeViewImmediate(dismissView);
        }
        dismissView = null;
    }

    private void showDismissTarget() {
        if (dismissView == null || dismissShown) return;
        dismissShown = true;
        // Placed on every show rather than once: the screen may have rotated since.
        int size = dpToPx(DISMISS_VIEW_DP);
        Map<String, Integer> screen = currentScreenSizePx();
        WindowManager.LayoutParams lp = (WindowManager.LayoutParams) dismissView.getLayoutParams();
        lp.x = (screen.get("width") - size) / 2;
        lp.y = screen.get("height") - navigationBarHeightPx() - dpToPx(DISMISS_BOTTOM_MARGIN_DP) - size;
        ((WindowManager) getSystemService(WINDOW_SERVICE)).updateViewLayout(dismissView, lp);
        dismissView.reset();
        dismissView.animate().cancel();
        dismissView.animate().alpha(1f).setDuration(150).start();
    }

    private void hideDismissTarget(boolean animate) {
        dismissCaptured = false;
        if (!dismissShown) return;
        dismissShown = false;
        dismissView.animate().cancel();
        if (animate) {
            dismissView.animate().alpha(0f).setDuration(150).start();
        } else {
            dismissView.setAlpha(0f);
        }
    }

    /// Sticks / unsticks as the finger crosses the magnet radius (AOSP
    /// MagnetizedObject.maybeConsumeMotionEvent). Returns true while stuck, so the caller leaves the
    /// window to the spring.
    private boolean updateMagnet() {
        if (!dismissShown) return false;
        int[] center = dismissView.centerOnScreen();
        if (center == null) return false;
        boolean inside = Math.hypot(fingerX - center[0], fingerY - center[1])
                < dpToPx(DISMISS_MAGNET_RADIUS_DP);
        if (inside == dismissCaptured) return dismissCaptured;
        velocityTracker.computeCurrentVelocity(1000);
        float vx = velocityTracker.getXVelocity();
        float vy = velocityTracker.getYVelocity();
        if (inside) {
            if (Math.abs(vx) > dp(STICK_MAX_X_VELOCITY_DP)) return false;
            setCaptured(true);
            startSpring(SpringTarget.DISMISS_TARGET, STICK_STIFFNESS, STICK_DAMPING_RATIO, vx, vy);
        } else {
            setCaptured(false);
            startSpring(SpringTarget.FINGER, TOUCH_STIFFNESS, TOUCH_DAMPING_RATIO, 0f, 0f);
        }
        return dismissCaptured;
    }

    /// What an ACTION_UP during a drag means. Stuck: dismiss, unless flung upward hard enough to
    /// tear free. Not stuck but flung fast at the target: fly in, then dismiss. Returns true when it
    /// dismisses — the animation finishes the job.
    private boolean releaseDismisses(float rawX, float rawY, float vx, float vy) {
        if (dismissCaptured) {
            if (-vy > dp(FLING_MIN_VELOCITY_DP)) return false;
            dismissOnArrival = true;
            if (!springing) playDismissAnimation();
            return true;
        }
        if (!isFlungAtTarget(rawX, rawY, vx, vy)) return false;
        setCaptured(true);
        dismissOnArrival = true;
        startSpring(SpringTarget.DISMISS_TARGET, STICK_STIFFNESS, STICK_DAMPING_RATIO, vx, vy);
        return true;
    }

    /// AOSP StackAnimationController.flingStackThenSpringToEdge, x only: the side the ball is on,
    /// unless flung towards the other side faster than ESCAPE_VELOCITY. It stays at the height it
    /// was released at, as the app's own snap did (AOSP also flings y; not adopted).
    ///
    /// Replaces the app's snap, which stepped the window from a 20ms Dart timer through the method
    /// channel: off the display's vsync, so measured on video about every other frame did not
    /// move at all (per-frame steps 76, 0, 0, 52, 31, 0, 0, 0, 24, …).
    private void springToEdge(float vx) {
        WindowManager.LayoutParams p = (WindowManager.LayoutParams) flutterView.getLayoutParams();
        float half = flutterView.getWidth() / 2f;
        float x = p.x + windowOffsetX + half;
        int screenWidth = currentScreenSizePx().get("width");
        float escape = dp(ESCAPE_VELOCITY_DP);
        boolean toLeft = x < screenWidth / 2f ? vx < escape : vx < -escape;
        edgeX = toLeft ? half : screenWidth - half;
        edgeY = p.y + windowOffsetY + flutterView.getHeight() / 2f;
        startSpring(SpringTarget.EDGE, EDGE_STIFFNESS, EDGE_DAMPING_RATIO, vx, 0f);
    }

    /// AOSP isForcefulFlingTowardsTarget: fast enough downwards, and the line of the fling crosses
    /// the target's row inside a band three target-widths wide centred on it (AOSP
    /// flingToTargetWidthPercent = 3, "width" being the target view's).
    private boolean isFlungAtTarget(float rawX, float rawY, float vx, float vy) {
        int[] center = dismissView.centerOnScreen();
        if (center == null || rawY >= center[1] || vy < dp(FLING_MIN_VELOCITY_DP)) return false;
        float xAtTargetRow = rawX + vx * (center[1] - rawY) / vy;
        return Math.abs(xAtTargetRow - center[0]) < dismissView.getWidth() * 3f / 2f;
    }

    private void setCaptured(boolean captured) {
        dismissCaptured = captured;
        dismissView.setCaptured(captured);
        flutterView.performHapticFeedback(captured
                ? HapticFeedbackConstants.CONTEXT_CLICK : HapticFeedbackConstants.CLOCK_TICK);
    }

    /// Hands the window to the spring, starting from where it is now with velocity (vx, vy).
    /// Assumes the TOP|LEFT anchoring the app uses (the offset captured at ACTION_DOWN does not hold
    /// for the mirrored gravities).
    private void startSpring(SpringTarget target, float stiffness, float dampingRatio, float vx, float vy) {
        WindowManager.LayoutParams p = (WindowManager.LayoutParams) flutterView.getLayoutParams();
        ballX = p.x + windowOffsetX + flutterView.getWidth() / 2f;
        ballY = p.y + windowOffsetY + flutterView.getHeight() / 2f;
        ballVx = vx;
        ballVy = vy;
        springTarget = target;
        springStiffness = stiffness;
        springDampingRatio = dampingRatio;
        if (springing) return;
        springing = true;
        lastSpringFrameNanos = 0;
        // A callback from a spring that was stopped earlier this frame may still be queued; left
        // there, both would run every frame from now on.
        Choreographer.getInstance().removeFrameCallback(springFrame);
        Choreographer.getInstance().postFrameCallback(springFrame);
    }

    private final Choreographer.FrameCallback springFrame = new Choreographer.FrameCallback() {
        @Override
        public void doFrame(long frameTimeNanos) {
            if (!springing || windowManager == null || flutterView == null) {
                springing = false;
                return;
            }
            float tx;
            float ty;
            if (springTarget == SpringTarget.FINGER) {
                tx = fingerX;
                ty = fingerY;
            } else if (springTarget == SpringTarget.EDGE) {
                tx = edgeX;
                ty = edgeY;
            } else {
                int[] center = dismissShown ? dismissView.centerOnScreen() : null;
                if (center == null) {
                    springing = false;
                    dismissOnArrival = false;
                    return;
                }
                tx = center[0];
                ty = center[1];
            }
            float dt = lastSpringFrameNanos == 0 ? 1f / 60
                    : Math.min((frameTimeNanos - lastSpringFrameNanos) / 1e9f, 0.05f);
            lastSpringFrameNanos = frameTimeNanos;
            // Unit mass: damping = 2ζ√k. Semi-implicit Euler in 2ms steps — one 16ms step is
            // unstable at the touch stiffness.
            float damping = 2f * springDampingRatio * (float) Math.sqrt(springStiffness);
            int steps = Math.max(1, (int) Math.ceil(dt / 0.002f));
            float h = dt / steps;
            for (int i = 0; i < steps; i++) {
                ballVx += (-springStiffness * (ballX - tx) - damping * ballVx) * h;
                ballVy += (-springStiffness * (ballY - ty) - damping * ballVy) * h;
                ballX += ballVx * h;
                ballY += ballVy * h;
            }
            // Settled by SpringAnimation's rule for pixel properties: within 1px, under 62.5px/s.
            // Chasing the finger, that is "caught up" — plain dragging takes over (AOSP
            // StackAnimationController.moveStackFromTouch).
            if (Math.hypot(tx - ballX, ty - ballY) < 1f && Math.hypot(ballVx, ballVy) < 62.5f) {
                ballX = tx;
                ballY = ty;
                springing = false;
            }
            placeBall();
            if (springing) {
                Choreographer.getInstance().postFrameCallback(this);
            } else if (dismissOnArrival && springTarget == SpringTarget.DISMISS_TARGET) {
                playDismissAnimation();
            }
        }
    };

    private void placeBall() {
        WindowManager.LayoutParams p = (WindowManager.LayoutParams) flutterView.getLayoutParams();
        p.x = Math.round(ballX - flutterView.getWidth() / 2f) - windowOffsetX;
        p.y = Math.round(ballY - flutterView.getHeight() / 2f) - windowOffsetY;
        windowManager.updateViewLayout(flutterView, p);
    }

    /// The ball shrinks into the target and the target fades after it; then the app is told.
    private void playDismissAnimation() {
        if (dismissing) return;
        dismissing = true;
        dismissOnArrival = false;
        springing = false;
        flutterView.performHapticFeedback(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.LONG_PRESS);
        if (dismissView != null) {
            dismissView.animate().alpha(0f).scaleX(0.8f).scaleY(0.8f)
                    .setStartDelay(80).setDuration(180).start();
        }
        flutterView.animate().scaleX(0f).scaleY(0f).alpha(0f)
                .setInterpolator(new AccelerateInterpolator())
                .setDuration(180)
                .withEndAction(this::notifyDismissed)
                .start();
    }

    private void notifyDismissed() {
        // The app saves what it holds in memory (an in-progress recording) and then calls
        // exitApp. If it can't be reached, exit anyway rather than leave an invisible ball behind.
        flutterChannel.invokeMethod("onDismissed", null, new MethodChannel.Result() {
            @Override
            public void success(Object result) {
            }

            @Override
            public void error(String code, String message, Object details) {
                exitApp();
            }

            @Override
            public void notImplemented() {
                exitApp();
            }
        });
    }

    /// Tears down everything this app runs and kills the process: the overlay window and its
    /// foreground service, and the app's tasks (also removed from recents). With the
    /// accessibility service left enabled, the system rebinds it and brings back a bare process —
    /// no Flutter engine, and AccessibilityListener ignores events while nobody listens.
    private void exitApp() {
        removeDismissTarget();
        ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        for (ActivityManager.AppTask task : am.getAppTasks()) {
            task.finishAndRemoveTask();
        }
        if (windowManager != null) {
            windowManager.removeView(flutterView);
            windowManager = null;
            flutterView.detachFromFlutterEngine();
        }
        isRunning = false;
        stopSelf();
        // Leave a moment for the stop to reach the system: killed while still start-requested,
        // the service would be scheduled for a restart.
        mAnimationHandler.postDelayed(
                () -> android.os.Process.killProcess(android.os.Process.myPid()), 300);
    }

    /// In raw screen coordinates, as AOSP does: the event's own coordinates are relative to a
    /// window that is itself moving under the finger.
    private void trackVelocity(MotionEvent event) {
        if (velocityTracker == null) velocityTracker = VelocityTracker.obtain();
        float offsetX = event.getRawX() - event.getX();
        float offsetY = event.getRawY() - event.getY();
        event.offsetLocation(offsetX, offsetY);
        velocityTracker.addMovement(event);
        event.offsetLocation(-offsetX, -offsetY);
    }

    private void recycleVelocityTracker() {
        if (velocityTracker == null) return;
        velocityTracker.recycle();
        velocityTracker = null;
    }

    private float dp(float value) {
        return value * mResources.getDisplayMetrics().density;
    }

    private static final class DismissTargetView extends View {
        private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float radius;
        private final float capturedRadius;
        /// 0 = idle (white ring with a white X, transparent inside), 1 = captured (the ring widened
        /// to sit around the ball, the X gone under it).
        private float progress;
        private ValueAnimator animator;

        DismissTargetView(Context context, float radius, float capturedRadius, float strokeWidth) {
            super(context);
            this.radius = radius;
            this.capturedRadius = capturedRadius;
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            stroke.setStrokeWidth(strokeWidth);
            stroke.setColor(Color.WHITE);
        }

        void reset() {
            if (animator != null) animator.cancel();
            progress = 0f;
            setScaleX(1f);
            setScaleY(1f);
            invalidate();
        }

        void setCaptured(boolean captured) {
            if (animator != null) animator.cancel();
            animator = ValueAnimator.ofFloat(progress, captured ? 1f : 0f);
            animator.setDuration(120);
            animator.addUpdateListener(a -> {
                progress = (float) a.getAnimatedValue();
                invalidate();
            });
            animator.start();
        }

        /// Null until laid out — before that getLocationOnScreen reports the origin.
        int[] centerOnScreen() {
            if (getWidth() == 0) return null;
            int[] loc = new int[2];
            getLocationOnScreen(loc);
            return new int[]{loc[0] + getWidth() / 2, loc[1] + getHeight() / 2};
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float cx = getWidth() / 2f;
            float cy = getHeight() / 2f;
            stroke.setAlpha(255);
            canvas.drawCircle(cx, cy, radius + (capturedRadius - radius) * progress, stroke);
            if (progress < 1f) {
                float a = radius * 0.36f;
                stroke.setAlpha(Math.round(255 * (1 - progress)));
                canvas.drawLine(cx - a, cy - a, cx + a, cy + a, stroke);
                canvas.drawLine(cx - a, cy + a, cx + a, cy - a, stroke);
            }
        }
    }

    private class TrayAnimationTimerTask extends TimerTask {
        int mDestX;
        int mDestY;
        WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();

        public TrayAnimationTimerTask() {
            super();
            mDestY = lastYPosition;
            switch (WindowSetup.positionGravity) {
                case "auto":
                    mDestX = (params.x + (flutterView.getWidth() / 2)) <= szWindow.x / 2 ? 0 : szWindow.x - flutterView.getWidth();
                    return;
                case "left":
                    mDestX = 0;
                    return;
                case "right":
                    mDestX = szWindow.x - flutterView.getWidth();
                    return;
                default:
                    mDestX = params.x;
                    mDestY = params.y;
                    break;
            }
        }

        @Override
        public void run() {
            mAnimationHandler.post(() -> {
                params.x = (2 * (params.x - mDestX)) / 3 + mDestX;
                params.y = (2 * (params.y - mDestY)) / 3 + mDestY;
                if (windowManager != null) {
                    windowManager.updateViewLayout(flutterView, params);
                }
                if (Math.abs(params.x - mDestX) < 2 && Math.abs(params.y - mDestY) < 2) {
                    TrayAnimationTimerTask.this.cancel();
                    mTrayAnimationTimer.cancel();
                }
            });
        }
    }


}