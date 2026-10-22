// Discard HTML cached by earlier HTMX versions, including one-time credentials.
try {
  sessionStorage.removeItem('htmx-history-cache');
  localStorage.removeItem('htmx-history-cache');
} catch (_) {}

document.addEventListener('change', (event) => {
  const field = event.target;
  if (field instanceof HTMLSelectElement && field.matches('[data-auto-submit]') && field.form) {
    HTMLFormElement.prototype.requestSubmit.call(field.form);
  }
});

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
document.addEventListener('htmx:responseError', (event) => {
  if (event.detail.xhr.getResponseHeader('X-ProCash-Error') === 'csrf') {
    const element = document.getElementById('network-error');
    if (element) {
      element.textContent = 'Срок действия формы истёк. Обновите страницу и отправьте её ещё раз.';
      element.hidden = false;
    }
  }
});
document.addEventListener('pageChanged', (event) => {
  document.body.setAttribute('hx-headers', JSON.stringify({'X-CSRF-Token': event.detail.csrf}));
  document.querySelectorAll('[data-section]').forEach((link) => {
    link.classList.toggle('nav-active', link.dataset.section === event.detail.active);
  });
});
