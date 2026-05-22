import { Controller } from "@hotwired/stimulus"

// Client-side filter for the sidebar conversation list. Matches the
// typed query against each conversation title and hides recency groups
// that end up with nothing visible.
export default class extends Controller {
  static targets = ["query", "item", "empty"]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      const match = !query || item.dataset.title.toLowerCase().includes(query)
      item.hidden = !match
    })

    this.element.querySelectorAll(".convo-group").forEach((group) => {
      group.hidden = !group.querySelector(".convo:not([hidden])")
    })

    if (this.hasEmptyTarget) {
      const anyVisible = this.itemTargets.some((item) => !item.hidden)
      this.emptyTarget.hidden = anyVisible
    }
  }
}
