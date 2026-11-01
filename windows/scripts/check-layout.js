/* Evaluate this read-only probe in the synthetic preview's current page. It checks the
   rendered geometry, rather than CSS source or jsdom's zero-size layout. */
(() => {
  const failures = [];
  const main = document.querySelector('.tray-page-content');
  if (!main) throw new Error('Tray panel is not mounted');
  const navOffsets = [...document.querySelectorAll('.comfort-history-nav button svg')].map(svg => {
    const icon = svg.getBoundingClientRect();
    const button = svg.parentElement.getBoundingClientRect();
    return Math.max(Math.abs(icon.x + icon.width / 2 - button.x - button.width / 2),
      Math.abs(icon.y + icon.height / 2 - button.y - button.height / 2));
  });
  if (navOffsets.some(offset => offset > 1)) failures.push('Calendar arrow is off center');
  const clippedCalendarPeriods = [...document.querySelectorAll('.comfort-history-nav > strong')]
    .filter(element => element.scrollWidth > element.clientWidth + 1 || element.scrollHeight > element.clientHeight + 1).length;
  if (clippedCalendarPeriods) failures.push('Calendar period text is clipped');
  const dayHeader = document.querySelector('.comfort-history-grid--day')
    ? document.querySelector('.comfort-history-weekdays > span') : null;
  const dayGrid = document.querySelector('.comfort-history-grid--day');
  const dayHeaderOffset = dayHeader && dayGrid ? (() => {
    const header = dayHeader.getBoundingClientRect(), grid = dayGrid.getBoundingClientRect();
    return Math.abs(header.left + header.width / 2 - grid.left - grid.width / 2);
  })() : 0;
  if (dayHeaderOffset > 1) failures.push('Day-view weekday is not centered over its date');
  const cloudCheckboxes = [...document.querySelectorAll('.cloud-share-option input[type="checkbox"]')];
  const cloudCheckboxStretch = cloudCheckboxes.some(input => {
    const bounds = input.getBoundingClientRect();
    return Math.abs(bounds.width - bounds.height) > 1;
  });
  if (cloudCheckboxStretch) failures.push('Cloud checkbox is stretched by text-field sizing');
  const controls = [...document.querySelectorAll('.tray-setting-row input, .tray-setting-row select')];
  const settingsOverflow = controls.some(control => {
    const field = control.closest('.tray-setting-row').getBoundingClientRect();
    const bounds = control.getBoundingClientRect();
    return bounds.left < field.left - 1 || bounds.right > field.right + 1;
  });
  if (settingsOverflow) failures.push('Settings control exceeds its row');
  const starts = controls.map(control => control.getBoundingClientRect().left);
  const columnSpread = starts.length ? Math.max(...starts) - Math.min(...starts) : 0;
  if (innerWidth > 700 && columnSpread > 1) failures.push('Settings controls do not share a column');
  const horizontalOverflow = [...document.querySelectorAll('.tray-page-content, .tray-page-tabs, .comfort-history-panel')]
    .some(element => element.scrollWidth > element.clientWidth + 1);
  if (horizontalOverflow) failures.push('Panel has horizontal overflow');
  const clippedTabs = [...document.querySelectorAll('.tray-page-tabs button')]
    .filter(element => element.scrollWidth > element.clientWidth + 1).length;
  if (clippedTabs) failures.push('Navigation text is clipped');
  const report = { pass: failures.length === 0, viewport: [innerWidth, innerHeight],
    calendarArrowOffset: Math.max(0, ...navOffsets), clippedCalendarPeriods, dayHeaderOffset, cloudCheckboxStretch, controlCount: controls.length,
    controlColumnSpread: columnSpread, settingsOverflow, horizontalOverflow, clippedTabs, failures };
  if (failures.length) throw new Error(JSON.stringify(report));
  return report;
})()
