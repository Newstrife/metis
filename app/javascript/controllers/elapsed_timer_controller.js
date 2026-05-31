import { Controller } from "@hotwired/stimulus"

// Shows a live elapsed counter ("Working for 24s") while an agent turn
// streams. Reads started_at as a Unix-ms timestamp from a data attribute
// and ticks every second. Stimulus disconnects it automatically when the
// indicator element is removed from the DOM (ChatBroadcaster#finish).
export default class extends Controller {
  static values = { startedAt: Number }
  static targets = ["label"]

  connect() {
    this._tick()
    this._interval = setInterval(() => this._tick(), 1000)
  }

  disconnect() {
    clearInterval(this._interval)
  }

  // ── private ──────────────────────────────────────────────────────────────

  _tick() {
    const elapsed = Math.floor((Date.now() - this.startedAtValue) / 1000)
    if (this.hasLabelTarget) this.labelTarget.textContent = this._format(elapsed)
  }

  _format(seconds) {
    if (seconds < 60) return `Working for ${seconds}s`
    const m = Math.floor(seconds / 60)
    const s = String(seconds % 60).padStart(2, "0")
    return `Working for ${m}m ${s}s`
  }
}
