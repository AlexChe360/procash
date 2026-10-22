// Launched by TestBrowserXSS against its temporary PostgreSQL schema and server.
const { chromium } = require('playwright-core');
const fs = require('node:fs');
const assert = require('node:assert/strict');

async function main() {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  const executablePath = process.env.CHROMIUM_PATH || (fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined);
  const browser = await chromium.launch({ executablePath, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  try {
    const context = await browser.newContext();
    const dialogs = [], errors = [], probes = [], violations = [];
    await context.exposeBinding('recordCSPViolation', (_, detail) => violations.push(detail));
    await context.addInitScript(() => {
      globalThis.__xss = 0;
      document.addEventListener('securitypolicyviolation', (event) => {
        globalThis.recordCSPViolation({ directive: event.effectiveDirective, blocked: event.blockedURI });
      });
    });
    context.on('page', (page) => {
      page.on('dialog', (dialog) => {
        if (dialog.type() === 'confirm' && dialog.message().startsWith('Выдать доступ и создать заведение?')) return dialog.accept();
        dialogs.push(dialog.message());
        return dialog.dismiss();
      });
      page.on('pageerror', (error) => errors.push(error.message));
    });
    await context.route('**/*', async (route) => {
      const url = new URL(route.request().url());
      if (url.pathname.startsWith('/__xss/template/')) {
        const index = Number(url.pathname.split('/').pop());
        // No CSP here: check template escaping independently of browser policy.
        return route.fulfill({ contentType: 'text/html; charset=utf-8', body: data.matrix[index].html });
      }
      if (url.pathname === '/__xss/probe') {
        probes.push(url.href);
        return route.fulfill({ body: 'Unexpected HTMX request' });
      }
      if (url.origin !== data.base) {
        // Keep these local tests independent of Google Fonts/network access.
        return route.fulfill({ contentType: 'text/css', body: '' });
      }
      return route.continue();
    });

    async function assertSafe(page, label) {
      const result = await page.evaluate(() => {
        const unsafe = [];
        for (const element of document.querySelectorAll('*')) {
          if (['IFRAME', 'OBJECT', 'EMBED', 'BASE'].includes(element.tagName) || element.id === 'xss-probe') unsafe.push(element.outerHTML);
          if (element.tagName === 'SCRIPT' && (!['/assets/app.js', '/assets/htmx.min.js'].includes(new URL(element.src, location.href).pathname) || element.textContent.trim())) unsafe.push(element.outerHTML);
          for (const attr of element.attributes) {
            if (/^on/i.test(attr.name) || attr.name === 'srcdoc' || (/^(href|src|action|formaction)$/i.test(attr.name) && /^\s*(javascript|vbscript|data):/i.test(attr.value))) unsafe.push(element.outerHTML);
          }
        }
        return { marker: globalThis.__xss, unsafe };
      });
      assert.equal(result.marker, 0, `${label}: script executed`);
      assert.deepEqual(result.unsafe, [], `${label}: executable markup or DOM clobbering injected`);
    }

    let next = 0;
    await Promise.all(Array.from({ length: 4 }, async () => {
      const page = await context.newPage();
      while (next < data.matrix.length) {
        const index = next++;
        await page.goto(`${data.base}/__xss/template/${index}`, { waitUntil: 'load' });
        await assertSafe(page, `${data.matrix[index].name}/${index}`);
      }
      await page.close();
    }));
    assert.deepEqual(probes, [], 'Injected HTMX attributes issued a request');
    assert.deepEqual(dialogs, []);
    assert.deepEqual(errors, []);
    console.log(`Template escaping passed for ${data.matrix.length} documents/fragments without CSP.`);

    const page = await context.newPage();
    const responses = [];
    page.on('response', (response) => { if (response.url().startsWith(data.base)) responses.push(response); });
    await page.goto(data.base + '/');
    assert.equal(await page.locator('h1').count(), 1);
    assert.equal(await page.locator('header .header-button').getAttribute('href'), '/connect');
    assert.equal(await page.locator('header').evaluate((e) => getComputedStyle(e).display), 'block');
    const homepageImages = await page.locator('img').evaluateAll((images) => images.map((image) => ({
      src: image.getAttribute('src'), loaded: image.complete && image.naturalWidth > 0,
    })));
    assert.ok(homepageImages.length > 0, 'Homepage must retain its payment logos');
    assert.deepEqual(homepageImages.filter((image) => !image.loaded), [], 'Homepage images must load');
    assert.deepEqual(responses.filter((response) => response.status() >= 400).map((response) => ({
      url: response.url(), status: response.status(),
    })), [], 'Homepage and its local resources must load successfully');
    const initialViewport = page.viewportSize();
    for (const width of [1440, 785, 390]) {
      await page.setViewportSize({ width, height: 940 });
      await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      assert.ok(await page.locator('.payment-logos img').isVisible(), `Payment logo is hidden at ${width}px`);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Homepage overflows at ${width}px`);
    }
    await page.setViewportSize(initialViewport);
    console.log('Homepage images and local resources loaded; layout checked at 1440, 785 and 390px.');
    await assertSafe(page, 'static homepage');
    await page.goto(data.base + '/connect');
    await page.waitForFunction(() => typeof htmx !== 'undefined');
    const config = await page.evaluate(() => ({ eval: htmx.config.allowEval, scripts: htmx.config.allowScriptTags, sameOrigin: htmx.config.selfRequestsOnly, history: htmx.config.historyCacheSize }));
    assert.deepEqual(config, { eval: false, scripts: false, sameOrigin: true, history: 0 });

    // Reflected values in a 422 response must remain text after an HTMX swap.
    await page.locator('[name=contact_name]').fill(data.payload);
    await page.locator('[name=email]').fill('new-request@example.test');
    await page.locator('[name=phone]').fill('+77011234567');
    await page.locator('[name=restaurant_name]').fill(data.payload);
    await page.locator('[name=city]').fill('Алматы');
    await page.locator('[name=comment]').fill('</textarea><img src=x onerror="globalThis.__xss=1">');
    await page.locator('[name=consent]').check();
    await page.locator('[name=email]').evaluate((e) => { e.type = 'text'; e.value = '"><svg/onload=globalThis.__xss=1>'; });
    await page.getByRole('button', { name: 'Отправить заявку', exact: true }).click();
    await page.locator('[role=alert]').waitFor();
    await assertSafe(page, 'reflected HTMX validation');
    await page.locator('[name=email]').fill('new-request@example.test');
    await page.locator('[name=consent]').check();
    await page.getByRole('button', { name: 'Отправить заявку', exact: true }).click();
    await page.waitForURL('**/connect?sent=1');
    await assertSafe(page, 'public application');

    async function login(email, expected, password = 'fixture-password') {
      await context.clearCookies();
      await page.goto(data.base + '/login');
      await page.locator('[name=email]').fill(email);
      await page.locator('[name=password]').fill(password);
      await page.getByRole('button', { name: 'Войти', exact: true }).click();
      await page.waitForURL(`**/${expected}`);
      await assertSafe(page, `${expected} login`);
    }
    await login('owner@example.test', 'dashboard');
    const restaurant = `/restaurants/${data.venue}`;
    for (const path of [restaurant, restaurant + '/tables', restaurant + `/tables/${data.table}`, restaurant + '/orders', restaurant + '/payments', restaurant + '/payments/freedom-pay/company', restaurant + '/payments/freedom-pay/restaurant', restaurant + '/payments/freedom-pay/review', restaurant + '/integrations/iiko', '/account', data.publicURL]) {
      await page.goto(data.base + path);
      await assertSafe(page, path);
      if (path === restaurant) assert.equal(await page.locator('[name=name]').inputValue(), data.payload);
      if (path === data.publicURL) assert.equal(await page.locator('h1').textContent(), data.payload);
    }
    const jsonResponse = await page.request.get(`${data.base}/api/v1/orders/current?restaurantId=${data.venue}&tableNumber=5`);
    assert.equal(jsonResponse.status(), 200);
    assert.match(jsonResponse.headers()['content-type'], /^application\/json/);
    assert.equal(jsonResponse.headers()['x-content-type-options'], 'nosniff');
    assert.equal((await jsonResponse.json()).items[0].name, data.payload);
    assert.ok(!(await jsonResponse.text()).includes('<img'), 'JSON output must escape HTML delimiters');
    const qrResponse = await page.request.get(`${data.base}${restaurant}/tables/${data.table}/qr.png`);
    assert.equal(qrResponse.headers()['content-type'], 'image/png');
    await page.goto(data.base + '/dashboard');
    await page.locator('[name=days]').selectOption('7');
    await page.waitForURL('**/dashboard?days=7');
    await page.waitForFunction(() => document.title === 'Обзор заведений — ProCash');
    await assertSafe(page, 'HTMX metrics filter');
    assert.equal(await page.evaluate(() => sessionStorage.getItem('htmx-history-cache')), null);
    await page.goto(data.base + '/account');
    await page.locator('[name=name]').fill('</textarea><svg/onload=globalThis.__xss=1>');
    await page.getByRole('button', { name: 'Сохранить данные', exact: true }).click();
    await page.waitForURL('**/account?saved=1');
    await assertSafe(page, 'stored profile');
    await login('admin@example.test', 'admin');
    const adminPaths = ['/admin/requests', `/admin/requests/${data.request}`, '/admin/users', '/admin/freedom-pay/applications', `/admin/freedom-pay/applications/${data.freedom}`, '/admin/iiko/applications', `/admin/iiko/applications/${data.iiko}`, '/admin/mail'];
    for (const path of adminPaths) {
      await page.goto(data.base + path);
      await assertSafe(page, path);
    }
    await page.goto(data.base + '/admin/requests');
    await page.locator('[name=status]').selectOption('NEW');
    await page.waitForURL('**/admin/requests?status=NEW');
    await assertSafe(page, 'HTMX request filter');
    await page.locator('tr').filter({ hasText: 'new-request@example.test' }).getByRole('link').click();
    await page.getByRole('button', { name: 'Создать кабинет и выдать доступ', exact: true }).click();
    await page.locator('#temporary-password').waitFor();
    const temporary = await page.locator('#temporary-password').textContent();
    await assertSafe(page, 'admin access grant');
    await login('new-request@example.test', 'account/password', temporary);
    await page.locator('[name=current_password]').fill(temporary);
    await page.locator('[name=password]').fill('browser-new-fixture-password');
    await page.locator('[name=password_confirmation]').fill('browser-new-fixture-password');
    await page.getByRole('button', { name: 'Установить пароль', exact: true }).click();
    await page.waitForURL('**/dashboard?password=changed');
    await assertSafe(page, 'mandatory password replacement');
    assert.equal(await page.evaluate(() => sessionStorage.getItem('htmx-history-cache')), null);

    await login('admin@example.test', 'admin');
    await page.locator(`a[href="/admin/restaurants/${data.venue}/delete"]`).click();
    await page.waitForURL(`**/admin/restaurants/${data.venue}/delete`);
    await assertSafe(page, 'restaurant deletion confirmation with hostile name');
    assert.ok(await page.locator('[name=confirm]').evaluate((element) => element.required && element.validity.valueMissing));
    await page.getByRole('link', { name: 'Отмена', exact: true }).click();
    await page.waitForURL(`**/restaurants/${data.venue}`);
    await page.getByRole('link', { name: 'Удалить заведение', exact: true }).click();
    await page.locator('[name=confirm]').check();
    await page.getByRole('button', { name: 'Удалить заведение', exact: true }).click();
    await page.waitForURL('**/restaurants?deleted=1');
    assert.equal(await page.locator(`a[href="/restaurants/${data.venue}"]`).count(), 0);
    assert.equal((await page.request.get(data.base + data.publicURL)).status(), 404);
    await page.goto(data.base + '/admin/users');
    await page.locator('tr').filter({ hasText: 'new-request@example.test' }).getByRole('link', { name: 'Удалить', exact: true }).click();
    await assertSafe(page, 'user deletion confirmation with hostile name');
    await page.locator('[name=confirm]').check();
    await page.getByRole('button', { name: 'Удалить пользователя', exact: true }).click();
    await page.waitForURL('**/admin/users?deleted=1');
    assert.equal(await page.locator('tr').filter({ hasText: 'new-request@example.test' }).count(), 0);
    console.log('Admin deletion passed: escaped confirmations, cancellation, restaurant/user removal and inactive QR links.');
    assert.deepEqual(dialogs, [], 'Unexpected JavaScript dialog');
    const original = await page.request.get(data.base + '/connect');
    const policy = original.headers()['content-security-policy'];
    assert.ok(policy && !policy.includes('unsafe-'), 'Strict CSP is absent');
    assert.deepEqual(violations, [], 'Normal pages violate CSP');
    assert.deepEqual(errors, []);

    // A same-origin script would pass script-src 'self'; HTMX must still remove
    // script elements from swapped responses rather than fetching/executing it.
    let fragmentScriptRequests = 0;
    await context.route('**/__xss/fragment-probe', (route) => route.fulfill({
      contentType: 'text/html',
      body: '<script src="/__xss/probe.js"></script><script>globalThis.__xss=1</script><p id="fragment-probe-result">ok</p>',
    }));
    await context.route('**/__xss/probe.js', (route) => {
      fragmentScriptRequests++;
      return route.fulfill({ contentType: 'application/javascript', body: 'globalThis.__xss=1' });
    });
    await page.evaluate(() => htmx.ajax('GET', '/__xss/fragment-probe', { target: '#workspace' }));
    await page.locator('#fragment-probe-result').waitFor();
    assert.equal(await page.locator('#workspace script').count(), 0);
    assert.equal(fragmentScriptRequests, 0, 'HTMX fetched a script from an HTML fragment');
    assert.equal(await page.evaluate(() => globalThis.__xss), 0);
    assert.deepEqual(violations, [], 'HTMX must remove scripts rather than relying on CSP');

    // Positive control: policy must block raw script tags and event handlers.
    await context.route('**/__xss/csp-probe', (route) => route.fulfill({
      contentType: 'text/html', headers: { 'Content-Security-Policy': policy },
      body: '<script>globalThis.__xss=1</script><img src="/missing-probe-image" onerror="globalThis.__xss=1"><button onclick="globalThis.__xss=1">probe</button>',
    }));
    await page.goto(data.base + '/__xss/csp-probe');
    await page.getByRole('button', { name: 'probe' }).click();
    assert.equal(await page.evaluate(() => globalThis.__xss), 0, 'CSP allowed inline code');
    assert.ok(violations.some((v) => v.directive === 'script-src-elem'));
    assert.ok(violations.some((v) => v.directive === 'script-src-attr'));
    assert.ok(responses.some((response) => response.request().headers()['hx-request'] === 'true' && response.headers()['content-security-policy'] === policy), 'HTMX responses lack CSP');
    console.log(`XSS checks passed: ${data.matrix.length} unprotected template documents/fragments, stored/reflected inputs, admin/owner/QR pages, working HTMX filters, and enforced CSP.`);
  } finally {
    await browser.close();
  }
}
main().catch((error) => { console.error(error); process.exit(1); });
