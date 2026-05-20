import { Controller } from "@hotwired/stimulus"

// Repopulates the model <select> with the models for the chosen
// provider. The catalog ({ provider: [{ value, label }] }) is passed in
// as a Stimulus value; the initial provider's models are server-rendered.
export default class extends Controller {
  static targets = ["provider", "model"]
  static values = { catalog: Object }

  providerChanged() {
    const models = this.catalogValue[this.providerTarget.value] || []
    this.modelTarget.replaceChildren(
      ...models.map((model) => {
        const option = document.createElement("option")
        option.value = model.value
        option.textContent = model.label
        return option
      })
    )
  }
}
