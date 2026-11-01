/* Read-only rendered geometry check for the synthetic compact surface. */
(() => {
  const panel = document.querySelector('.floating-summary');
  if (!panel) throw new Error('Floating summary is not mounted');
  const clipped = [panel, ...panel.querySelectorAll('*')].filter(element =>
    element.clientWidth > 0 && (element.scrollWidth > element.clientWidth + 1
      || element.scrollHeight > element.clientHeight + 1));
  const failures = clipped.map(element => `Clipped content: ${element.className}`);
  const bounds = panel.getBoundingClientRect();
  for (const button of panel.querySelectorAll('button')) {
    const rect = button.getBoundingClientRect();
    if (rect.left < bounds.left || rect.top < bounds.top || rect.right > bounds.right || rect.bottom > bounds.bottom) {
      failures.push(`Button outside card: ${button.getAttribute('aria-label')}`);
    }
  }
  const report = { pass: failures.length === 0, viewport: [innerWidth, innerHeight],
    metricCount: panel.querySelectorAll('.floating-summary-metric').length, failures };
  if (failures.length) throw new Error(JSON.stringify(report));
  return report;
})()
