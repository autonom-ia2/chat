import { chromium } from 'playwright';

const BASE_URL = process.env.AUTONOMIA_BASE_URL || 'https://agents.autonomia.site';
const EMAIL = process.env.AUTONOMIA_EMAIL;
const PASSWORD = process.env.AUTONOMIA_PASSWORD;

if (!EMAIL || !PASSWORD) {
  throw new Error(
    'Set AUTONOMIA_EMAIL and AUTONOMIA_PASSWORD before running this script.'
  );
}

const outputPath =
  process.env.AUTONOMIA_DROPDOWN_SCREENSHOT || '/tmp/branded-dropdown.png';

const firstVisible = async (page, selectors) => {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    try {
      if (await locator.isVisible({ timeout: 1500 })) return locator;
    } catch {
      // Try the next selector; the login UI changes independently from Chatwoot.
    }
  }
  return null;
};

const clickAutonomiaSso = async page => {
  const candidates = [
    page.getByRole('button', { name: /autonom/i }),
    page.getByRole('link', { name: /autonom/i }),
    page.getByText(/sign in with autonomia/i),
    page.getByText(/login with autonomia/i),
    page.getByText(/entrar com autonomia/i),
    page.getByText(/autonom\.ia/i),
  ];

  for (const candidate of candidates) {
    try {
      if (await candidate.first().isVisible({ timeout: 1500 })) {
        await candidate.first().click();
        return true;
      }
    } catch {
      // Try the next label.
    }
  }

  return false;
};

const fillAuthLogin = async page => {
  const emailInput = await firstVisible(page, [
    'input[type="email"]',
    'input[name="email"]',
    'input[name="username"]',
    'input[autocomplete="username"]',
    'input[placeholder*="email" i]',
  ]);

  if (emailInput) await emailInput.fill(EMAIL);

  const passwordInput = await firstVisible(page, [
    'input[type="password"]',
    'input[name="password"]',
    'input[autocomplete="current-password"]',
    'input[placeholder*="password" i]',
    'input[placeholder*="senha" i]',
  ]);

  if (passwordInput) await passwordInput.fill(PASSWORD);

  const submitButton = await firstVisible(page, [
    'button[type="submit"]',
    'input[type="submit"]',
    'button:has-text("Login")',
    'button:has-text("Entrar")',
    'button:has-text("Sign in")',
    'button:has-text("Continuar")',
  ]);

  if (submitButton) await submitButton.click();

  return Boolean(emailInput && passwordInput && submitButton);
};

const clickIfVisible = async (page, locators) => {
  for (const locator of locators) {
    try {
      if (await locator.first().isVisible({ timeout: 1500 })) {
        await locator.first().click();
        return true;
      }
    } catch {
      // Try next locator.
    }
  }
  return false;
};

const clearAuthPrompts = async page => {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const skippedPasskey = await clickIfVisible(page, [
      page.getByRole('button', { name: /agora não/i }),
      page.getByRole('link', { name: /agora não/i }),
      page.getByText(/agora não/i),
      page.getByRole('button', { name: /not now/i }),
      page.getByText(/not now/i),
    ]);

    if (skippedPasskey) {
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(1500);
      continue;
    }

    const continued = await clickIfVisible(page, [
      page.getByRole('button', { name: /^continuar$/i }),
      page.getByRole('button', { name: /^continue$/i }),
      page.getByText(/^continuar$/i),
    ]);

    if (continued) {
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(1500);
      continue;
    }

    break;
  }
};

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

page.on('console', msg => console.log('[browser]', msg.type(), msg.text()));
page.on('pageerror', error => console.log('[pageerror]', error.message));

await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
await page.waitForLoadState('networkidle').catch(() => {});

const clickedSso = await clickAutonomiaSso(page);
console.log('Clicked autonomia SSO:', clickedSso);
await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(1500);

if (page.url().includes('auth.autonomia.site')) {
  const filled = await fillAuthLogin(page);
  console.log('Filled auth login:', filled);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await clearAuthPrompts(page);
}

await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 45000 }).catch(() => {});
await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

console.log('URL after login:', page.url());

if (!/\/app\/accounts\/\d+/.test(page.url()) && page.url().includes('sso_auth_token=')) {
  const url = new URL(page.url());
  const email = url.searchParams.get('email');
  const ssoAuthToken = url.searchParams.get('sso_auth_token');

  const response = await page.request.post(`${BASE_URL}/auth/sign_in`, {
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'AutonomiaPlaywrightSsoDiagnostic',
    },
    data: {
      email,
      sso_auth_token: ssoAuthToken,
    },
  });

  const responseBody = await response.json().catch(() => null);
  console.log(
    JSON.stringify(
      {
        manualSsoStatus: response.status(),
        manualSsoBodyKeys: responseBody ? Object.keys(responseBody) : [],
        manualSsoHasData: Boolean(responseBody?.data),
      },
      null,
      2
    )
  );

  if (response.ok() && responseBody?.data) {
    const authHeaders = response.headers();
    await page.context().addCookies([
      {
        name: 'cw_d_session_info',
        value: encodeURIComponent(JSON.stringify(authHeaders)),
        domain: new URL(BASE_URL).hostname,
        path: '/',
        sameSite: 'Lax',
      },
    ]);

    const accountId =
      responseBody.data.account_id || responseBody.data.accounts?.[0]?.id;
    await page.goto(`${BASE_URL}/app/accounts/${accountId}/dashboard`, {
      waitUntil: 'domcontentloaded',
    });
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  }
}

if (!/\/app\/accounts\/\d+/.test(page.url())) {
  const bodyText = await page.locator('body').innerText().catch(() => '');
  const inputState = await page.locator('input').evaluateAll(inputs =>
    inputs.map((input, index) => ({
      index,
      type: input.getAttribute('type'),
      name: input.getAttribute('name'),
      autocomplete: input.getAttribute('autocomplete'),
      placeholder: input.getAttribute('placeholder'),
      valueLength: input.value.length,
      ariaInvalid: input.getAttribute('aria-invalid'),
      validationMessage: input.validationMessage,
    }))
  );

  console.log(
    JSON.stringify(
      {
        loginDidNotComplete: true,
        bodyText: bodyText.replace(/\s+/g, ' ').slice(0, 2000),
        inputState,
      },
      null,
      2
    )
  );
  await page.screenshot({ path: '/tmp/branded-dropdown-login-failure.png', fullPage: true });
  console.log('loginFailureScreenshot=/tmp/branded-dropdown-login-failure.png');
  await browser.close();
  process.exit(1);
}

const profileTriggerCandidates = [
  'button:has-text("roberto")',
  'button:has-text("Roberto")',
  'button[title*="Roberto"]',
  'button[title*="roberto"]',
  '.sidebar button:has(img)',
  'aside button:has(img)',
  'button:has(.i-lucide-chevron-down)',
];

let clicked = false;
for (const selector of profileTriggerCandidates) {
  const locator = page.locator(selector).last();
  if (!(await locator.count())) continue;

  try {
    await locator.click({ timeout: 5000 });
    clicked = true;
    console.log('Clicked profile trigger:', selector);
    break;
  } catch (error) {
    console.log('Failed candidate:', selector, error.message);
  }
}

if (!clicked) {
  const buttons = await page.locator('button').evaluateAll(nodes =>
    nodes.slice(0, 80).map((node, index) => ({
      index,
      text: node.innerText,
      title: node.getAttribute('title'),
      className: node.className,
      aria: node.getAttribute('aria-label'),
    }))
  );
  console.log(JSON.stringify({ buttons }, null, 2));
  throw new Error('Could not find/click profile trigger');
}

await page.waitForTimeout(800);

const data = await page.evaluate(() => {
  const readStyle = element => {
    const style = getComputedStyle(element);
    return {
      backgroundColor: style.backgroundColor,
      backgroundImage: style.backgroundImage,
      backdropFilter: style.backdropFilter || style.webkitBackdropFilter || null,
      color: style.color,
      opacity: style.opacity,
    };
  };

  const dropdowns = [...document.querySelectorAll('.sidebar-branded-dropdown')].map(
    (root, index) => {
      const body = root.querySelector('.n-dropdown-body');
      return {
        index,
        rootTag: root.tagName,
        rootClass: root.getAttribute('class'),
        rootStyleAttribute: root.getAttribute('style'),
        rootComputed: readStyle(root),
        bodyClass: body?.getAttribute('class') || null,
        bodyStyleAttribute: body?.getAttribute('style') || null,
        bodyComputed: body ? readStyle(body) : null,
        text: body?.innerText?.slice(0, 500) || null,
      };
    }
  );

  const bodyCandidates = [...document.querySelectorAll('.n-dropdown-body')].map(
    (body, index) => ({
      index,
      parentClass: body.parentElement?.getAttribute('class'),
      className: body.getAttribute('class'),
      styleAttribute: body.getAttribute('style'),
      computed: readStyle(body),
      text: body.innerText?.slice(0, 160),
    })
  );

  return {
    url: location.href,
    htmlClass: document.documentElement.getAttribute('class'),
    colorScheme: getComputedStyle(document.documentElement).colorScheme,
    globalConfig: window.globalConfig
      ? {
          sidebarBackgroundColor: window.globalConfig.SIDEBAR_BACKGROUND_COLOR,
          gitSha: window.globalConfig.GIT_SHA,
        }
      : null,
    dropdowns,
    bodyCandidates,
  };
});

console.log(JSON.stringify(data, null, 2));
await page.screenshot({ path: outputPath, fullPage: true });
console.log(`screenshot=${outputPath}`);

await browser.close();
