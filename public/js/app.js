document.getElementById('menu-toggle')?.addEventListener('click', function () {
    const open = document.getElementById('navigation').classList.toggle('pc-open');
    this.setAttribute('aria-expanded', String(open));
});
