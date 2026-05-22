import { Controller } from "@hotwired/stimulus"

// The message composer textarea: Enter sends, Shift+Enter inserts a
// newline. Enter is ignored mid-IME-composition (so confirming a
// Chinese/Japanese candidate doesn't send) and while a turn streams.
export default class extends Controller {
  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    const form = this.element.form
    // A Stop button in the composer means a turn is already streaming.
    if (form.querySelector(".send.stop")) return

    form.requestSubmit()
  }
}
