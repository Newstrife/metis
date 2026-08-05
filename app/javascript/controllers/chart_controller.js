import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Renders ```chart fenced blocks in agent message bodies as live Chart.js
// charts. Commonmarker emits <pre lang="chart"><code>{json}</code></pre>;
// connect() swaps each for a canvas + a source toggle, keeping the original
// <pre> inside the wrapper so "view code" can bring it back.
//
// Attached to the .chat-content body. During streaming Turbo replaces that
// body's innerHTML on every delta, so:
//   - scans run on a MutationObserver, coalesced with requestAnimationFrame
//   - a block whose JSON doesn't parse yet (still streaming) is left alone
//     and retried on the next pass
//   - charts whose canvas was wiped by a re-render are destroyed on sweep
// A block that parses but Chart.js rejects (bad type, missing data) reverts
// to the plain code block and is marked so it isn't retried.
export default class extends Controller {
  static values = { sourceLabel: String, chartLabel: String }

  connect() {
    this.charts = []
    this.observer = new MutationObserver(() => this.scheduleScan())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.scheduleScan()
  }

  disconnect() {
    this.observer.disconnect()
    cancelAnimationFrame(this.raf)
    this.charts.forEach((chart) => chart.destroy())
    this.charts = []
  }

  toggle(event) {
    const wrap = event.currentTarget.closest(".chat-chart")
    const showingSource = wrap.classList.toggle("chat-chart--show-source")
    event.currentTarget.textContent = showingSource ? this.chartLabelValue : this.sourceLabelValue
  }

  scheduleScan() {
    cancelAnimationFrame(this.raf)
    this.raf = requestAnimationFrame(() => this.scan())
  }

  scan() {
    this.sweep()
    this.element.querySelectorAll('pre[lang="chart"]:not([data-chart-invalid])').forEach((pre) => {
      if (pre.closest(".chat-chart")) return // already rendered
      this.renderBlock(pre)
    })
  }

  // Drop Chart instances whose canvas a streaming re-render removed.
  sweep() {
    this.charts = this.charts.filter((chart) => {
      if (chart.canvas.isConnected) return true
      chart.destroy()
      return false
    })
  }

  renderBlock(pre) {
    const code = pre.querySelector("code")
    const text = (code ? code.textContent : pre.textContent).trim()

    let config
    try {
      config = JSON.parse(text)
    } catch {
      return // still streaming, or simply not JSON — leave the code block
    }
    if (!config || typeof config !== "object" || Array.isArray(config)) {
      pre.dataset.chartInvalid = "true"
      return
    }

    const wrap = document.createElement("div")
    wrap.className = "chat-chart"
    const frame = document.createElement("div")
    frame.className = "chat-chart-frame"
    const canvas = document.createElement("canvas")
    frame.appendChild(canvas)
    const toggle = document.createElement("button")
    toggle.type = "button"
    toggle.className = "chat-chart-toggle"
    toggle.dataset.action = "chart#toggle"
    toggle.textContent = this.sourceLabelValue
    wrap.append(frame, toggle)

    pre.replaceWith(wrap)
    pre.classList.add("chat-chart-source")
    wrap.appendChild(pre)

    try {
      this.charts.push(new Chart(canvas, this.withDefaults(config)))
    } catch {
      // Chart.js rejected the config — fall back to the code block for good.
      wrap.replaceWith(pre)
      pre.classList.remove("chat-chart-source")
      pre.dataset.chartInvalid = "true"
    }
  }

  withDefaults(config) {
    const css = getComputedStyle(this.element)
    const ink = css.getPropertyValue("--ink-3").trim() || "#8f9189"
    const line = css.getPropertyValue("--line").trim() || "#e7e5df"
    Chart.defaults.color = ink
    Chart.defaults.borderColor = line
    Chart.defaults.font.family = css.getPropertyValue("--fb").trim() || Chart.defaults.font.family
    return {
      ...config,
      options: { responsive: true, maintainAspectRatio: false, ...(config.options || {}) }
    }
  }
}
