// Theme toggle. The initial value is stamped on <html> before first paint by
// an inline script in the layout; this only handles the switch.
//
// Nothing else on this site is scripted. The charts are server-rendered SVG
// and CSS with their real values in the markup, so a chart is never blank
// because a script did not run.
(function () {
  var toggle = document.querySelector("[data-theme-toggle]");
  if (!toggle) return;

  toggle.addEventListener("click", function () {
    var next = document.documentElement.dataset.theme === "light" ? "dark" : "light";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("applebench-theme", next);
    } catch (e) {
      // Private browsing denies storage; the toggle still works for this page.
    }
  });
})();
