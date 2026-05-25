import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() { this._schedule() }
  disconnect() { this._cancel() }
  pause() { this._cancel() }
  resume() { this._schedule() }

  _schedule() {
    this._cancel()
    this.timer = setTimeout(() => this._dismiss(), this.delayValue)
  }

  _cancel() {
    clearTimeout(this.timer)
    this.timer = null
  }

  _dismiss() {
    this.element.classList.add("flash-toast--leaving")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
    // Fallback for interrupted/missing transition.
    setTimeout(() => this.element.remove(), 400)
  }
}
