document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-copy]');
  if (button && navigator.clipboard) {
    const value = document.getElementById(button.dataset.copy);
    if (value) navigator.clipboard.writeText(value.textContent).then(() => { button.textContent = 'Скопировано'; }).catch(() => {});
  }
});
document.addEventListener('htmx:sendError', () => {
  const element = document.getElementById('network-error');
  if (element) element.hidden = false;
});
document.addEventListener('pageChanged', (event) => {
  document.body.setAttribute('hx-headers', JSON.stringify({'X-CSRF-Token': event.detail.csrf}));
  document.querySelectorAll('[data-section]').forEach((link) => {
    link.classList.toggle('nav-active', link.dataset.section === event.detail.active);
  });
});
