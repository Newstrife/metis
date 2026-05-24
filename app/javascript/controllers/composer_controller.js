import { Controller } from "@hotwired/stimulus"

// The message composer textarea:
//
// 1. Submit on Enter — Enter sends, Shift+Enter inserts a newline.
//    Enter is ignored mid-IME-composition (so confirming a
//    Chinese/Japanese candidate doesn't send) and while a turn streams.
//
// 2. Auto-focus — the textarea is focused on:
//    a. Initial page load and Turbo Drive navigations (via connect())
//    b. After the assistant finishes streaming (detected via
//       turbo:before-stream-render targeting composer_actions)
//    Focus is skipped on touch-primary devices (phones/tablets) to avoid
//    popping the virtual keyboard unexpectedly.
export default class extends Controller {
  connect() {
    this._focusUnlessMobile()
    this._streamRenderHandler = this._handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this._streamRenderHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._streamRenderHandler)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    const form = this.element.form
    // A Stop button in the composer means a turn is already streaming.
    if (form.querySelector(".send.stop")) return

    form.requestSubmit()
  }

  // ── private ──────────────────────────────────────────────────────────────

  _focusUnlessMobile() {
    // Avoid popping the virtual keyboard on touch-primary devices.
    if (window.matchMedia("(pointer: coarse)").matches) return
    this.element.focus()
  }

  _handleStreamRender(event) {
    // Only care about updates to composer_actions (ChatJob swaps Stop→Send
    // when a streaming turn ends).
    const stream = event.detail?.newStream
    if (stream?.getAttribute("target") !== "composer_actions") return

    // Schedule after Turbo has applied the DOM update so we can confirm the
    // stop button is gone before stealing focus.
    requestAnimationFrame(() => {
      const form = this.element.closest("form")
      if (!form?.querySelector(".send.stop")) this._focusUnlessMobile()
    })
  }
}
