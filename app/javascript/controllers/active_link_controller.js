import { Controller } from "@hotwired/stimulus"

// Marks the link whose href matches `location.pathname` with `.on`.
//
// Sidebar conversation links target the #main turbo-frame, so picking
// one swaps the right pane without re-rendering the sidebar — which
// means the server-rendered `.on` class on the previously-active row
// would stick. We sync client-side instead: any `data-active-link-
// target="link"` inside this controller's element gets the class
// toggled whenever the URL changes (clicks, back/forward, restored
// frame visits) or a new link target connects (endless-scroll items).
export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.update = this.update.bind(this)
    document.addEventListener("turbo:load", this.update)
    document.addEventListener("turbo:frame-load", this.update)
    this.update()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.update)
    document.removeEventListener("turbo:frame-load", this.update)
  }

  linkTargetConnected(link) {
    this.mark(link)
  }

  update() {
    this.linkTargets.forEach((link) => this.mark(link))
  }

  mark(link) {
    const linkPath = new URL(link.href, location.origin).pathname
    link.classList.toggle("on", linkPath === location.pathname)
  }
}
