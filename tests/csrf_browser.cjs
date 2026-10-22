// Uses local TLS servers and reserved .test domains; no production requests.
const { chromium } = require('playwright-core');
const fs = require('node:fs');
const assert = require('node:assert/strict');

async function main() {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  const executablePath = process.env.CHROMIUM_PATH || (fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined);
  const browser = await chromium.launch({ executablePath, headless: true, args: [
    '--no-sandbox', '--disable-dev-shm-usage', '--no-proxy-server',
    '--host-resolver-rules=MAP app.procash.test 127.0.0.1, MAP evil.procash.test 127.0.0.1, MAP attacker.other.test 127.0.0.1',
  ] });
  try {
    const errors = [];
    async function makeContext() {
      const context = await browser.newContext({ ignoreHTTPSErrors: true });
      context.setDefaultTimeout(15000);
      context.on('page', (page) => page.on('pageerror', (error) => errors.push(error.message)));
      return context;
    }
    async function observe(context, path, method) {
      const response = await context.request.get(data.observer + '/__csrf-observations', { timeout: 10000 });
      assert.equal(response.status(), 200);
      const observed = (await response.json()).findLast((item) => item.path === path && item.method === method);
      assert.ok(observed, `Server did not receive ${method} ${path}`);
      return observed;
    }
    async function login(context, email, destination) {
      const page = await context.newPage();
      await page.goto(data.base + '/login');
      await page.locator('[name=email]').fill(email);
      await page.locator('[name=password]').fill('fixture-password');
      await page.getByRole('button', { name: 'Войти', exact: true }).click();
      await page.waitForURL('**/' + destination);
      return page;
    }
    let blocked = 0;
    const evilPages = new Map();
    async function forge(context, source, path, values) {
      let evil = evilPages.get(context);
      if (!evil) { evil = await context.newPage(); evilPages.set(context, evil); }
      await evil.goto(source);
      const responsePromise = evil.waitForResponse((response) => response.url() === data.base + path && response.request().method() === 'POST');
      await evil.evaluate(({ action, values }) => {
        const form = document.createElement('form');
        form.method = 'POST'; form.action = action;
        for (const [name, value] of Object.entries(values)) {
          const input = document.createElement('input'); input.name = name; input.value = value; form.append(input);
        }
        const button = document.createElement('button'); button.id = 'csrf-forge-submit'; button.type = 'submit'; button.textContent = 'Submit'; form.append(button);
        document.body.append(form);
      }, { action: data.base + path, values });
      await evil.locator('#csrf-forge-submit').click({ noWaitAfter: true });
      const response = await responsePromise;
      await evil.waitForURL(data.base + path, { waitUntil: 'load' });
      assert.equal(response.status(), 403, `${source} forged ${path}`);
      const observed = await observe(context, path, 'POST');
      assert.equal(observed.origin, source);
      assert.equal(observed.site, source === data.sibling ? 'same-site' : 'cross-site');
      if (source === data.sibling) assert.equal(observed.session, true, 'SameSite must not be the reason this sibling-origin attack failed');
      blocked++;
      await evil.waitForLoadState('load');
    }
    const ownerContext = await makeContext();
    const owner = await login(ownerContext, 'owner@example.test', 'dashboard');
    const cookies = await ownerContext.cookies(data.base);
    for (const name of ['__Host-procash_session', '__Host-procash_csrf']) {
      const cookie = cookies.find((cookie) => cookie.name === name);
      assert.ok(cookie && cookie.httpOnly && cookie.secure && cookie.path === '/' && cookie.sameSite === 'Lax' && cookie.domain === 'app.procash.test');
    }

    // HEAD is a CORS-safelisted method: this request really includes the victim's
    // cookies from an untrusted sibling origin, but must remain read-only.
    const evil = await ownerContext.newPage();
    await evil.goto(data.sibling);
    const target = `${data.base}/account?name=FORGED&email=owner%40example.test`;
    const headResponse = evil.waitForResponse((response) => response.url() === target && response.request().method() === 'HEAD');
    await evil.evaluate((target) => fetch(target, { method: 'HEAD', credentials: 'include', mode: 'no-cors', signal: AbortSignal.timeout(10000) }).then(() => true), target);
    const response = await headResponse;
    const head = await observe(ownerContext, new URL(target).pathname + new URL(target).search, 'HEAD');
    assert.equal(response.status(), 200);
    assert.equal(head.site, 'same-site');
    assert.equal(head.session, true);
    await evil.close();
    await owner.goto(data.base + '/account');
    assert.equal(await owner.locator('[name=name]').inputValue(), 'Original', 'HEAD changed the profile');

    for (const source of [data.sibling, data.external]) {
      await forge(ownerContext, source, '/account', { name: 'FORGED', email: 'owner@example.test' });
      await forge(ownerContext, source, '/login', { email: 'attacker@example.test', password: 'fixture-password' });
      await forge(ownerContext, source, '/logout', {});
      await forge(ownerContext, source, '/account/password', { current_password: 'fixture-password', password: 'forged-new-password', password_confirmation: 'forged-new-password' });
      await forge(ownerContext, source, `/payments/${data.payment}/mock/success`, {});
      await forge(ownerContext, source, '/connect', { contact_name: 'FORGED', email: 'forged@example.test', phone: '+77011234567', restaurant_name: 'FORGED', city: 'Алматы', consent: 'yes' });
    }
    // Even disclosure of a valid token would not grant cross-origin authority.
    await forge(ownerContext, data.sibling, '/account', { _csrf: cookies.find((cookie) => cookie.name === '__Host-procash_csrf').value, name: 'FORGED', email: 'owner@example.test' });
    await owner.goto(data.base + '/account');
    assert.equal(await owner.locator('[name=email]').inputValue(), 'owner@example.test');
    assert.equal(await owner.locator('[name=name]').inputValue(), 'Original');

    // A rejected stale HTMX form gives an actionable message and cannot mutate.
    await owner.locator('[name=_csrf]').last().evaluate((element) => { element.value = 'invalid'; });
    await owner.locator('[name=name]').fill('FORGED');
    const rejected = owner.waitForResponse((response) => response.url() === data.base + '/account' && response.request().method() === 'POST');
    await owner.getByRole('button', { name: 'Сохранить данные', exact: true }).click();
    assert.equal((await rejected).status(), 403);
    await owner.locator('#network-error').waitFor({ state: 'visible' });
    assert.match(await owner.locator('#network-error').textContent(), /Обновите страницу/);
    await owner.reload();
    await owner.locator('[name=name]').fill('Legitimate');
    await owner.getByRole('button', { name: 'Сохранить данные', exact: true }).click();
    await owner.waitForURL('**/account?saved=1');
    assert.equal(await owner.locator('[name=name]').inputValue(), 'Legitimate');

    const adminContext = await makeContext();
    const admin = await login(adminContext, 'admin@example.test', 'admin');
    for (const source of [data.sibling, data.external]) {
      await forge(adminContext, source, `/admin/users/${data.owner}/disable`, {});
      await forge(adminContext, source, `/admin/requests/${data.request}/approve`, {});
    }
    await admin.goto(data.base + '/admin');
    assert.equal(await admin.locator('h1').textContent(), 'Панель ProCash');
    assert.deepEqual(errors, []);
    console.log(`Browser CSRF checks passed: ${blocked} rejected same-site/cross-site forms, read-only authenticated HEAD, production cookies, stale HTMX errors and legitimate profile updates.`);
  } finally {
    await browser.close();
  }
}
main().catch((error) => { console.error(error); process.exit(1); });
