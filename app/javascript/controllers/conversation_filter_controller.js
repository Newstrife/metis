import { Controller } from "@hotwired/stimulus"

// Client-side filter for the sidebar conversation list. Matches the
// typed query against each conversation title and hides recency
// group headers whose visible items all dropped out.
export default class extends Controller {
  static targets = ["query", "item", "empty"]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      const match = !query || item.dataset.title.toLowerCase().includes(query)
      item.hidden = !match
    })

    // The list is flat: `.grp-label` divs interleaved with `.convo`
    // links (and a trailing sentinel). Walk the list once and hide a
    // header iff every `.convo` between it and the next header is
    // hidden.
    const list = this.element.querySelector("#convos-list")
    if (list) {
      let currentHeader = null
      let anyVisible = false
      const flush = () => { if (currentHeader) currentHeader.hidden = !anyVisible }
      for (const child of list.children) {
        if (child.classList.contains("grp-label")) {
          flush()
          currentHeader = child
          anyVisible = false
        } else if (child.classList.contains("convo") && !child.hidden) {
          anyVisible = true
        }
      }
      flush()
    }

    if (this.hasEmptyTarget) {
      const anyVisible = this.itemTargets.some((item) => !item.hidden)
      this.emptyTarget.hidden = anyVisible
    }
  }

  // New rows arriving via endless-scroll: re-apply the active filter so
  // they don't pop in visible while a query is in effect.
  itemTargetConnected() {
    if (this.hasQueryTarget && this.queryTarget.value.trim()) this.filter()
  }
}
