import { Controller } from "@hotwired/stimulus"

// Bottom-of-sidebar user popup: opens the panel, swaps the theme live,
// persists the new theme via PATCH /profile/theme so it follows the
// user across devices. The no-flash head script reads the same
// localStorage + server value on next load.
export default class extends Controller {
  static targets = ["panel", "themeButton"]
  static values  = { themeUrl: String }

  connect() {
    this.onDocClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
  }

  disconnect() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.element.classList.contains("open") ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("open")
    // Defer so the click that opened it doesn't immediately close it.
    setTimeout(() => {
      document.addEventListener("click", this.onDocClick)
      document.addEventListener("keydown", this.onKey)
    }, 0)
  }

  close() {
    this.element.classList.remove("open")
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  }

  switchTheme(event) {
    const theme = event.currentTarget.dataset.theme
    this.#applyTheme(theme)
    this.#markActive(theme)
    this.#persist(theme)
  }

  // "system" means honour OS preference — clear the localStorage
  // override and resolve via matchMedia for the immediate flip.
  #applyTheme(theme) {
    const root = document.documentElement
    if (theme === "system") {
      localStorage.removeItem("metisTheme")
      const dark = matchMedia("(prefers-color-scheme: dark)").matches
      root.dataset.theme = dark ? "dark" : "light"
    } else {
      localStorage.setItem("metisTheme", theme)
      root.dataset.theme = theme
    }
  }

  #markActive(theme) {
    this.themeButtonTargets.forEach((btn) => {
      btn.classList.toggle("on", btn.dataset.theme === theme)
    })
  }

  #persist(theme) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.themeUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
        "Accept": "application/json"
      },
      body: JSON.stringify({ theme }),
      credentials: "same-origin"
    })
  }
}
