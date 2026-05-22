import { Controller } from "@hotwired/stimulus"

// Keeps the message stream pinned to the bottom as content streams in.
// The stream target is the scrollable element; the whole pane is watched
// for mutations so streamed text deltas and appended messages both scroll.
export default class extends Controller {
  static targets = ["messages", "scroll"]

  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      characterData: true,
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    const el = this.hasScrollTarget ? this.scrollTarget : this.element
    el.scrollTop = el.scrollHeight
  }
}
