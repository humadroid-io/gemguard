import { Controller } from "@hotwired/stimulus"

const themes = ["auto", "light", "dark"]

export default class extends Controller {
  static targets = ["label", "option"]
  static values = { storageKey: { type: String, default: "gemguard.theme" } }

  connect() {
    this.apply(this.savedTheme)
  }

  select(event) {
    this.apply(event.params.value)
  }

  apply(theme) {
    theme = themes.includes(theme) ? theme : "auto"

    if (theme === "auto") {
      document.documentElement.removeAttribute("data-theme")
      this.clearSavedTheme()
    } else {
      document.documentElement.dataset.theme = theme
      this.saveTheme(theme)
    }

    this.updateControls(theme)
  }

  get savedTheme() {
    try {
      return localStorage.getItem(this.storageKeyValue)
    } catch (_) {
      return "auto"
    }
  }

  saveTheme(theme) {
    try {
      localStorage.setItem(this.storageKeyValue, theme)
    } catch (_) {}
  }

  clearSavedTheme() {
    try {
      localStorage.removeItem(this.storageKeyValue)
    } catch (_) {}
  }

  updateControls(theme) {
    this.labelTarget.textContent = this.labelFor(theme)

    this.optionTargets.forEach((option) => {
      const active = option.dataset.themeValueParam === theme

      option.classList.toggle("active", active)
      option.setAttribute("aria-checked", active.toString())
    })
  }

  labelFor(theme) {
    return theme.charAt(0).toUpperCase() + theme.slice(1)
  }
}
