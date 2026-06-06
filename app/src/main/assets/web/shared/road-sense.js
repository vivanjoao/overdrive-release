/**
 * Overdrive — RoadSense Settings Module
 *
 * Mirrors recording.js / surveillance.js:
 *   - loadConfig() reads the current state from the daemon (GET
 *     /api/settings/unified -> config.roadSense).
 *   - each control persists immediately on change via fetch() POST
 *     /api/settings/unified { section: "roadSense", data: { ... } }.
 *     (XHR POST bodies are dropped in the in-app WebView — always fetch().)
 *
 * Config keys (the `roadSense` UCM section; RoadSenseConfig.kt reads these
 * exact names):
 *   enabled, warnEnabled, warnMode ("visual"|"audio"|"both"),
 *   warnLeadSeconds (default 4, 2..8), warnConfidenceThreshold (0..1, default 0),
 *   warnSeverityMinor / warnSeverityModerate / warnSeveritySevere,
 *   calibrationMode, crowdUpload, crowdDownload, syncWorkerUrl.
 *
 * The two delete actions hit live daemon endpoints (RoadSenseApiHandler, routed
 * from HttpServer):
 *   POST /api/roadsense/delete-local  — wipe on-device calibrations/detections
 *   POST /api/roadsense/delete-cloud  — wipe this device's uploaded rows
 */

window.BYD = window.BYD || {};

BYD.roadSense = {
    config: {
        enabled: false,
        warnEnabled: true,
        warnMode: 'both',
        warnLeadSeconds: 4,
        // Stored 0..1 in the config; the slider works in whole percent (0..100).
        warnConfidenceThreshold: 0,
        warnSeverityMinor: true,
        warnSeverityModerate: true,
        warnSeveritySevere: true,
        calibrationMode: false,
        crowdUpload: false,
        crowdDownload: false,
        syncWorkerUrl: ''
    },

    async init() {
        await this.loadConfig();
        this.updateUI();

        // Re-read config when the user switches back to the tab (unless a
        // write is mid-flight). Cheap and keeps the page in sync with the
        // native settings UI / daemon-side changes.
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible' && !this._writing) {
                this.reload();
            }
        });
    },

    async reload() {
        await this.loadConfig();
        this.updateUI();
    },

    async loadConfig() {
        try {
            const resp = await fetch('/api/settings/unified');
            const data = await resp.json();
            if (data && data.success && data.config && data.config.roadSense) {
                const rs = data.config.roadSense;
                const c = this.config;
                if (typeof rs.enabled === 'boolean') c.enabled = rs.enabled;
                if (typeof rs.warnEnabled === 'boolean') c.warnEnabled = rs.warnEnabled;
                if (rs.warnMode) c.warnMode = String(rs.warnMode).toLowerCase();

                if (typeof rs.warnLeadSeconds === 'number') {
                    let v = Math.round(rs.warnLeadSeconds);
                    if (v < 2) v = 2; if (v > 8) v = 8;
                    c.warnLeadSeconds = v;
                }
                if (typeof rs.warnConfidenceThreshold === 'number') {
                    let t = rs.warnConfidenceThreshold;
                    if (t < 0) t = 0; if (t > 1) t = 1;
                    c.warnConfidenceThreshold = t;
                }
                if (typeof rs.warnSeverityMinor === 'boolean') c.warnSeverityMinor = rs.warnSeverityMinor;
                if (typeof rs.warnSeverityModerate === 'boolean') c.warnSeverityModerate = rs.warnSeverityModerate;
                if (typeof rs.warnSeveritySevere === 'boolean') c.warnSeveritySevere = rs.warnSeveritySevere;
                if (typeof rs.calibrationMode === 'boolean') c.calibrationMode = rs.calibrationMode;
                if (typeof rs.crowdUpload === 'boolean') c.crowdUpload = rs.crowdUpload;
                if (typeof rs.crowdDownload === 'boolean') c.crowdDownload = rs.crowdDownload;
                if (typeof rs.syncWorkerUrl === 'string') c.syncWorkerUrl = rs.syncWorkerUrl;
            }
        } catch (e) {
            console.warn('RoadSense: failed to load config:', e);
        }
    },

    /**
     * Merge-write one or more keys into the roadSense UCM section. fetch()
     * (never XHR) so the WebView doesn't drop the POST body. Returns true on
     * a successful write so callers can revert the control on failure.
     */
    async _save(delta) {
        this._writing = true;
        try {
            const resp = await fetch('/api/settings/unified', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ section: 'roadSense', data: delta })
            });
            const data = await resp.json();
            return !!(data && data.success);
        } catch (e) {
            console.warn('RoadSense: save failed:', e);
            return false;
        } finally {
            this._writing = false;
        }
    },

    // ==================== UI sync ====================

    updateUI() {
        const c = this.config;

        this._setChecked('rsEnabled', c.enabled);
        this._setBadge('rsStatusBadge', c.enabled);

        this._setChecked('rsCalibrationMode', c.calibrationMode);

        this._setChecked('rsWarnEnabled', c.warnEnabled);
        this._setBadge('rsWarnBadge', c.enabled && c.warnEnabled);

        // Master gate: every other card only takes effect while RoadSense is on
        // (master_enable_desc). When it's off, dim + disable the dependent cards so
        // their toggles don't read as live next to an OFF badge — the contradiction
        // a first-run user hits (defaults show warnEnabled/severities ON, but the
        // Warnings badge is OFF because the master is off).
        this._applyMasterGate(c.enabled);

        // Warn mode button group.
        document.querySelectorAll('#rsWarnModeBtns .btn-toggle').forEach(btn =>
            btn.classList.toggle('active', btn.dataset.value === c.warnMode));

        // Lead-time slider.
        const leadSlider = document.getElementById('rsWarnLeadSlider');
        if (leadSlider) leadSlider.value = c.warnLeadSeconds;
        this._setLeadLabel(c.warnLeadSeconds);

        // Confidence slider (config 0..1 -> percent 0..100).
        const confPct = Math.round(c.warnConfidenceThreshold * 100);
        const confSlider = document.getElementById('rsWarnConfSlider');
        if (confSlider) confSlider.value = confPct;
        this._setConfLabel(confPct);

        // Per-severity chimes.
        this._setChecked('rsSeverityMinor', c.warnSeverityMinor);
        this._setChecked('rsSeverityModerate', c.warnSeverityModerate);
        this._setChecked('rsSeveritySevere', c.warnSeveritySevere);

        // Crowdsource.
        this._setChecked('rsCrowdUpload', c.crowdUpload);
        this._setChecked('rsCrowdDownload', c.crowdDownload);
        const urlInput = document.getElementById('rsSyncWorkerUrl');
        if (urlInput) urlInput.value = c.syncWorkerUrl || '';
    },

    _setChecked(id, on) {
        const el = document.getElementById(id);
        if (el) el.checked = !!on;
    },

    /**
     * Visually gate the dependent cards on the master `enabled` flag. The General
     * card holding the master switch stays fully live; every OTHER card (Warnings,
     * Crowdsource, Data) is dimmed + made non-interactive while the master is off,
     * so a first-run user doesn't see live-looking toggles next to an OFF badge.
     * Their checked STATE is preserved (so flipping master back on reveals the
     * saved selection) — we only block interaction, we don't change values.
     */
    _applyMasterGate(masterOn) {
        document.querySelectorAll('.card').forEach(card => {
            // Leave the master switch's own card always interactive.
            if (card.querySelector('#rsEnabled')) return;
            card.classList.toggle('rs-gated', !masterOn);
            // Block pointer + keyboard interaction on the controls when gated,
            // without touching their checked/value (so state survives a toggle).
            card.querySelectorAll('input, button, .btn-toggle').forEach(ctrl => {
                if (!masterOn) {
                    ctrl.setAttribute('disabled', 'disabled');
                    ctrl.setAttribute('aria-disabled', 'true');
                } else {
                    ctrl.removeAttribute('disabled');
                    ctrl.removeAttribute('aria-disabled');
                }
            });
        });
    },

    _setBadge(id, on) {
        const badge = document.getElementById(id);
        if (!badge) return;
        badge.textContent = on ? BYD.i18n.t('status.on') : BYD.i18n.t('status.off');
        badge.className = 'status-badge ' + (on ? 'active' : 'inactive');
    },

    _setLeadLabel(seconds) {
        const el = document.getElementById('rsWarnLeadValue');
        if (!el) return;
        const tmpl = BYD.i18n.t('road_sense.unit_seconds', { n: seconds });
        el.textContent = (tmpl && tmpl !== 'road_sense.unit_seconds') ? tmpl : (seconds + 's');
    },

    _setConfLabel(pct) {
        const el = document.getElementById('rsWarnConfValue');
        if (el) el.textContent = pct + '%';
    },

    // ==================== Control handlers ====================

    async toggleEnabled() {
        const el = document.getElementById('rsEnabled');
        if (!el) return;
        const on = el.checked;
        const ok = await this._save({ enabled: on });
        if (ok) {
            this.config.enabled = on;
            this._setBadge('rsStatusBadge', on);
            this._setBadge('rsWarnBadge', on && this.config.warnEnabled);
            // Live-update the dependent-card gate so toggling the master on/off
            // immediately enables/dims Warnings/Crowdsource/Data.
            this._applyMasterGate(on);
            this._toastSaved();
        } else {
            el.checked = !on;
            this._toastFailed();
        }
    },

    async toggleCalibrationMode() {
        const el = document.getElementById('rsCalibrationMode');
        if (!el) return;
        const on = el.checked;
        const ok = await this._save({ calibrationMode: on });
        if (ok) { this.config.calibrationMode = on; this._toastSaved(); }
        else { el.checked = !on; this._toastFailed(); }
    },

    async toggleWarnEnabled() {
        const el = document.getElementById('rsWarnEnabled');
        if (!el) return;
        const on = el.checked;
        const ok = await this._save({ warnEnabled: on });
        if (ok) {
            this.config.warnEnabled = on;
            this._setBadge('rsWarnBadge', this.config.enabled && on);
            this._toastSaved();
        } else { el.checked = !on; this._toastFailed(); }
    },

    async setWarnMode(mode) {
        if (mode !== 'visual' && mode !== 'audio' && mode !== 'both') return;
        const prev = this.config.warnMode;
        // Optimistic UI — reflect immediately, revert if the write fails.
        document.querySelectorAll('#rsWarnModeBtns .btn-toggle').forEach(btn =>
            btn.classList.toggle('active', btn.dataset.value === mode));
        const ok = await this._save({ warnMode: mode });
        if (ok) { this.config.warnMode = mode; this._toastSaved(); }
        else {
            document.querySelectorAll('#rsWarnModeBtns .btn-toggle').forEach(btn =>
                btn.classList.toggle('active', btn.dataset.value === prev));
            this._toastFailed();
        }
    },

    // Slider live-label is updated on every input; the durable write is
    // debounced so dragging doesn't hammer the daemon.
    updateWarnLead(value) {
        let v = parseInt(value, 10);
        if (isNaN(v)) v = 4;
        if (v < 2) v = 2; if (v > 8) v = 8;
        this.config.warnLeadSeconds = v;
        this._setLeadLabel(v);
        this._debounceSave('warnLeadSeconds', { warnLeadSeconds: v });
    },

    updateWarnConf(value) {
        let pct = parseInt(value, 10);
        if (isNaN(pct)) pct = 0;
        if (pct < 0) pct = 0; if (pct > 100) pct = 100;
        const t = pct / 100;
        this.config.warnConfidenceThreshold = t;
        this._setConfLabel(pct);
        this._debounceSave('warnConfidenceThreshold', { warnConfidenceThreshold: t });
    },

    _debounceSave(key, delta) {
        this._saveTimers = this._saveTimers || {};
        if (this._saveTimers[key]) clearTimeout(this._saveTimers[key]);
        const self = this;
        this._saveTimers[key] = setTimeout(function () {
            self._saveTimers[key] = null;
            self._save(delta).then(function (ok) {
                if (!ok) self._toastFailed();
            });
        }, 250);
    },

    async toggleSeverity(level) {
        const map = {
            minor: { id: 'rsSeverityMinor', key: 'warnSeverityMinor' },
            moderate: { id: 'rsSeverityModerate', key: 'warnSeverityModerate' },
            severe: { id: 'rsSeveritySevere', key: 'warnSeveritySevere' }
        };
        const m = map[level];
        if (!m) return;
        const el = document.getElementById(m.id);
        if (!el) return;
        const on = el.checked;
        const delta = {}; delta[m.key] = on;
        const ok = await this._save(delta);
        if (ok) { this.config[m.key] = on; this._toastSaved(); }
        else { el.checked = !on; this._toastFailed(); }
    },

    async toggleCrowdUpload() {
        const el = document.getElementById('rsCrowdUpload');
        if (!el) return;
        const on = el.checked;
        const ok = await this._save({ crowdUpload: on });
        if (ok) { this.config.crowdUpload = on; this._toastSaved(); }
        else { el.checked = !on; this._toastFailed(); }
    },

    async toggleCrowdDownload() {
        const el = document.getElementById('rsCrowdDownload');
        if (!el) return;
        const on = el.checked;
        const ok = await this._save({ crowdDownload: on });
        if (ok) { this.config.crowdDownload = on; this._toastSaved(); }
        else { el.checked = !on; this._toastFailed(); }
    },

    async saveWorkerUrl() {
        const input = document.getElementById('rsSyncWorkerUrl');
        if (!input) return;
        const url = (input.value || '').trim();
        const ok = await this._save({ syncWorkerUrl: url });
        if (ok) { this.config.syncWorkerUrl = url; this._toastSaved(); }
        else { this._toastFailed(); }
    },

    // ==================== Destructive actions ====================
    //
    // Two SEPARATE deletes with distinct confirms, both backed by live handlers
    // (RoadSenseApiHandler):
    //   POST /api/roadsense/delete-local  — wipe on-device calibrations + labels.
    //   POST /api/roadsense/delete-cloud  — wipe this device's uploaded rows
    //                                        (server scopes by the rotating
    //                                        roadSense.deviceId).

    async deleteLocal() {
        const msg = BYD.i18n.t('road_sense.confirm_delete_local');
        const prompt = (msg && msg !== 'road_sense.confirm_delete_local')
            ? msg
            : 'Delete all RoadSense calibrations stored on this device? This cannot be undone.';
        if (!confirm(prompt)) return;
        const btn = document.getElementById('rsDeleteLocalBtn');
        if (btn) btn.disabled = true;
        try {
            const resp = await fetch('/api/roadsense/delete-local', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const data = await resp.json();
            if (data && data.success) {
                this._toast('road_sense.delete_local_done', 'Local calibrations deleted', 'success');
            } else {
                this._toast('road_sense.delete_failed', 'Delete failed', 'error');
            }
        } catch (e) {
            console.warn('RoadSense: delete-local failed:', e);
            this._toast('road_sense.delete_failed', 'Delete failed', 'error');
        } finally {
            if (btn) btn.disabled = false;
        }
    },

    async deleteCloud() {
        const msg = BYD.i18n.t('road_sense.confirm_delete_cloud');
        const prompt = (msg && msg !== 'road_sense.confirm_delete_cloud')
            ? msg
            : 'Delete the RoadSense detections you uploaded from the shared cloud map? This cannot be undone.';
        if (!confirm(prompt)) return;
        const btn = document.getElementById('rsDeleteCloudBtn');
        if (btn) btn.disabled = true;
        try {
            const resp = await fetch('/api/roadsense/delete-cloud', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const data = await resp.json();
            if (data && data.success) {
                this._toast('road_sense.delete_cloud_done', 'Cloud calibrations deleted', 'success');
            } else {
                this._toast('road_sense.delete_failed', 'Delete failed', 'error');
            }
        } catch (e) {
            console.warn('RoadSense: delete-cloud failed:', e);
            this._toast('road_sense.delete_failed', 'Delete failed', 'error');
        } finally {
            if (btn) btn.disabled = false;
        }
    },

    // ==================== Toast helpers ====================

    _toast(key, fallback, type) {
        if (!(BYD.utils && BYD.utils.toast)) return;
        const t = BYD.i18n.t(key);
        BYD.utils.toast((t && t !== key) ? t : fallback, type);
    },

    _toastSaved() {
        this._toast('road_sense.saved', 'Saved', 'success');
    },

    _toastFailed() {
        this._toast('road_sense.save_failed', 'Save failed', 'error');
    }
};

// Alias mirroring RecSettings / SurvSettings naming.
window.RoadSenseSettings = BYD.roadSense;
