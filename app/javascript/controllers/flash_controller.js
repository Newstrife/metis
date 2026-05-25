import { Controller } from "@hotwired/stimulus"

// Auto-dismisses the flash toast a few seconds after it renders.
// Hovering the toast cancels the dismissal so a slow reader (or
// someone aiming for the Undo button) doesn't get robbed of it.
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this._schedule()
  }

  disconnect() {
    this._cancel()
  }

  pause() {
    this._cancel()
  }

  resume() {
    this._schedule()
  }

  _schedule() {
    this._cancel()
    this.timer = setTimeout(() => this._dismiss(), this.delayValue)
  }

  _cancel() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  _dismiss() {
    this.element.classList.add("flash-toast--leaving")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
    // Belt-and-suspenders in case the transition is interrupted or absent.
    setTimeout(() => this.element.remove(), 400)
  }
}
