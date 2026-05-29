import { Controller } from "@hotwired/stimulus"

// Some connector pickers (Linear) store an opaque id as the agent-
// facing value but show a human-readable name to the operator. Each
// <option> carries a data-display attribute with that name; this
// controller copies it into a hidden input on change so the form
// submits both fields. Sync on connect too, in case the picker
// re-renders with a pre-selected value.
export default class extends Controller {
  static targets = ["select", "display"]

  connect() { this.sync() }

  sync() {
    if (!this.hasSelectTarget || !this.hasDisplayTarget) return
    const selected = this.selectTarget.selectedOptions[0]
    this.displayTarget.value = selected?.dataset.display || ""
  }
}
