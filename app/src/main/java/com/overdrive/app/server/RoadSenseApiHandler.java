package com.overdrive.app.server;

import com.overdrive.app.logging.DaemonLogger;

import org.json.JSONObject;

import java.io.OutputStream;

/**
 * RoadSense HTTP API — backs the road-sense.html settings page's destructive
 * "Data" actions (R-SET-5). Runs in the daemon process, so it calls the
 * RoadSense stores directly (no IPC hop needed — they're in-process singletons).
 *
 * Endpoints:
 *  - POST /api/roadsense/delete-local → wipe on-device hazards + ground-truth labels
 *  - POST /api/roadsense/delete-cloud → wipe this device's uploaded cloud rows
 *
 * The page calls these via fetch() (POST). Config (enable/warn/crowd toggles) is
 * NOT here — that flows through the normal /api/settings/unified path into the
 * `roadSense` UCM section, which RoadSenseConfig reads.
 */
public class RoadSenseApiHandler {

    private static final String TAG = "RoadSenseApiHandler";
    private static final DaemonLogger logger = DaemonLogger.getInstance(TAG);

    public static boolean handle(String method, String path, String body, OutputStream out) throws Exception {
        if (path.equals("/api/roadsense/delete-local") && method.equals("POST")) {
            handleDeleteLocal(out);
            return true;
        }
        if (path.equals("/api/roadsense/delete-cloud") && method.equals("POST")) {
            handleDeleteCloud(out);
            return true;
        }
        return false;
    }

    /**
     * "Delete local calibrations" (R-SET-5): clears the on-device hazard store AND
     * the Calibration-Mode ground-truth labels. Two SEPARATE stores, both wiped —
     * this is the local half of the two-independent-toggles requirement.
     */
    private static void handleDeleteLocal(OutputStream out) throws Exception {
        long hazards;
        int labels;
        try {
            hazards = com.overdrive.app.roadsense.store.RoadSenseStore.getInstance().deleteAllLocal();
        } catch (Throwable t) {
            logger.warn(TAG + ": delete-local hazards failed: " + t.getMessage());
            hazards = -1;
        }
        try {
            labels = com.overdrive.app.roadsense.label.GroundTruthStore.getInstance().deleteAll();
        } catch (Throwable t) {
            logger.warn(TAG + ": delete-local labels failed: " + t.getMessage());
            labels = -1;
        }
        // "Delete local" also clears route coverage — the user's mapped-tile history
        // is local calibration data too (R-SET-5). Note: per-vehicle calibration
        // (calQuietCount/calMeanSq) is intentionally NOT wiped here — it's a property
        // of the car, not the mapped routes, and re-learning it is a 10-min cost.
        try {
            com.overdrive.app.roadsense.RoadSenseController rs =
                com.overdrive.app.daemon.CameraDaemon.getRoadSense();
            if (rs != null) rs.clearCoverage();
        } catch (Throwable t) {
            logger.warn(TAG + ": delete-local coverage failed: " + t.getMessage());
        }
        JSONObject resp = new JSONObject();
        resp.put("success", true);
        resp.put("hazardsDeleted", hazards);
        resp.put("labelsDeleted", labels);
        logger.info(TAG + ": deleted local — hazards=" + hazards + " labels=" + labels);
        HttpResponse.sendJson(out, resp.toString());
    }

    /**
     * "Delete cloud calibrations" (R-SET-5): wipe this device's uploaded rows from
     * the crowdsource backend. Wired: delegates to RoadSenseController.deleteCloudUploads()
     * → RoadSenseSyncProvider.deleteOwnUploads() (Cloudflare edge POST /delete) and
     * clears the local tile cursors. Reports success=false (not a silent OK) when
     * RoadSense isn't running or the backend call fails.
     */
    private static void handleDeleteCloud(OutputStream out) throws Exception {
        JSONObject resp = new JSONObject();
        com.overdrive.app.roadsense.RoadSenseController rs =
                com.overdrive.app.daemon.CameraDaemon.getRoadSense();
        if (rs == null) {
            resp.put("success", false);
            resp.put("error", "RoadSense not running");
            HttpResponse.sendJson(out, resp.toString());
            return;
        }
        boolean ok = false;
        try {
            ok = rs.deleteCloudUploads();
        } catch (Throwable t) {
            logger.warn(TAG + ": delete-cloud failed: " + t.getMessage());
        }
        resp.put("success", ok);
        if (!ok) resp.put("error", "cloud delete failed (check sync config / connectivity)");
        logger.info(TAG + ": delete-cloud ok=" + ok);
        HttpResponse.sendJson(out, resp.toString());
    }
}
