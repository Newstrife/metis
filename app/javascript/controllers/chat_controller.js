import { Controller } from "@hotwired/stimulus"

// Keeps the message list scrolled to the bottom as content streams in.
export default class extends Controller {
  static targets = ["messages"]

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
    window.scrollTo({ top: document.body.scrollHeight })
  }
}
