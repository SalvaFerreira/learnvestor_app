// End-to-end walkthrough of the app in a browser:
//   sign in → onboarding → lesson (with one mistake) → practice (earns the heart back)
//   → tools → buy a stock → portfolio → profile
//
// Needs the web build served at APP_URL (default http://127.0.0.1:51973), built with
// SUPABASE_URL pointing to the demo API started with `npm run dev` in tools/db-tests.
// CHROME_PATH uses an installed Chrome; otherwise Playwright's Chromium is used.
// On failure a screenshot is saved to tools/e2e/artifacts/.

import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const APP_URL = process.env.APP_URL ?? 'http://127.0.0.1:51973';
const RUN = Date.now() % 1_000_000;
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined, headless: true });
const page = await browser.newPage({ viewport: { width: 412, height: 915 }, locale: 'en-US' });
page.setDefaultTimeout(10_000);
const errors = [];
page.on('pageerror', (e) => errors.push(`${e.message} ${(e.stack ?? '').split('\n').slice(0, 4).join(' | ')}`));

const wait = (ms) => page.waitForTimeout(ms);

/** Flutter exposes widgets through its accessibility tree: buttons, checkboxes, text.
 *  Retries for a while so screen transitions can finish. */
async function tap(name, { exact = false, timeout = 10_000 } = {}) {
  const candidates = () => [
    page.getByRole('tab', { name, exact: true }),
    page.getByRole('button', { name, exact }),
    page.getByRole('checkbox', { name, exact }),
    page.getByRole('radio', { name, exact }),
    page.getByText(name, { exact }),
    page.getByLabel(name, { exact }),
    page.locator(`[aria-label*="${name.replaceAll('"', '\\"')}"]`),
  ];
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    for (const locator of candidates()) {
      if (await locator.count()) {
        await locator.first().click();
        return;
      }
    }
    await wait(250);
  }
  throw new Error(`nothing to tap named "${name}"`);
}

/** Focuses the text field labelled [field] (falls back to the only/last field on screen). */
async function type(field, text) {
  const named = page.getByRole('textbox', { name: field });
  const target = (await named.count()) ? named.first() : page.getByRole('textbox').last();
  await target.click();
  await page.keyboard.type(text);
}

/** Text may be a DOM text node or merged into a semantics node's aria-label. */
const visible = async (text) =>
  (await page.getByText(text, { exact: false }).count()) > 0 ||
  (await page.locator(`[aria-label*="${text.replaceAll('"', '\\"')}"]`).count()) > 0;

async function expectText(text, timeout = 10_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await visible(text)) return;
    await wait(250);
  }
  throw new Error(`expected to see "${text}"`);
}

async function answerAndContinue(option) {
  await tap(option);
  await tap('Check');
  await wait(600);
  await tap('Continue');
  await wait(500);
}

/** Answers whichever exercise of "How Banks Work" is on screen, always correctly. */
async function answerBankExercise() {
  if (await visible('main way a bank makes money')) return answerAndContinue('Charging more interest');
  if (await visible('deposits up to')) return answerAndContinue('True');
  if (await visible('everyday spending')) return answerAndContinue('current');
  if (await visible('most liquid')) {
    for (const item of ['Cash in your wallet', 'Money in a current account', 'A 12-month term deposit', 'A house']) {
      await tap(item);
      await wait(200);
    }
    await tap('Check');
    await wait(600);
    await tap('Continue');
    await wait(500);
    return;
  }
  throw new Error('unknown exercise on screen');
}

/** The bot answers faster than the server's anti-cheat minimum (2 s per exercise): wait and
 *  use the app's "Try again", which resubmits the same answers. */
async function finishDespiteSpeed() {
  await wait(1500);
  if (await visible('too fast')) {
    await wait(9000);
    await tap('Try again');
  }
}

const steps = [
  ['open the app', async () => {
    await page.goto(APP_URL);
    await wait(5000);
    await page.locator('flt-semantics-placeholder').dispatchEvent('click'); // enable the accessibility tree
    await expectText('Send code');
  }],
  ['sign in with an email code', async () => {
    await type('Email', `e2e${RUN}@learnvestor.test`);
    await tap('Send code');
    await expectText('We sent a code');
    await type('6-digit code', '123456');
    await tap('Verify');
    await expectText("Let's set up your profile");
  }],
  ['complete onboarding', async () => {
    await type('Username', `e2e_${RUN}`);
    await tap('18-24');
    await tap('I accept the Terms');
    await tap('Start learning');
    await expectText('Experience Progress');
  }],
  ['finish a lesson with one mistake', async () => {
    await tap('Learn', { exact: true });
    await tap('How Banks Work');
    await tap('Continue'); // info card
    await answerAndContinue('Printing new money'); // wrong on purpose → retried at the end
    for (let i = 0; i < 4; i++) await answerBankExercise();
    await finishDespiteSpeed();
    await expectText('Lesson complete!');
    await expectText('First Steps');
    await tap('Done');
  }],
  ['practice gives the lost heart back', async () => {
    await tap('Practice');
    await expectText('Check');
    for (let i = 0; i < 4; i++) await answerBankExercise();
    await finishDespiteSpeed();
    await expectText('Practice complete!');
    await expectText('+1 heart recovered!');
    await tap('Done');
  }],
  ['use the calculators', async () => {
    await tap('Home', { exact: true });
    await tap('Tools');
    await expectText('Final value');
    await tap('Emergency fund');
    await expectText('months to go');
    await page.goBack();
  }],
  ['buy a stock with virtual money', async () => {
    await tap('Explore', { exact: true });
    await tap('Apple Inc.');
    await expectText('Buy AAPL');
    await page.getByRole('textbox').last().click();
    await page.keyboard.type('50');
    await tap('Buy AAPL');
    await expectText('You bought AAPL');
  }],
  ['see it in the portfolio', async () => {
    await tap('Portfolio', { exact: true });
    await expectText('Apple Inc.');
    await expectText('1 holding');
  }],
  ['profile shows progress and achievements', async () => {
    await tap('Profile', { exact: true });
    await expectText(`@e2e_${RUN}`);
    await expectText('First Trade');
  }],
];

let failed = false;
for (const [name, run] of steps) {
  try {
    await run();
    console.log(`✔ ${name}`);
  } catch (error) {
    failed = true;
    mkdirSync('artifacts', { recursive: true });
    const shot = `artifacts/failed-${name.replaceAll(' ', '-')}.png`;
    await page.screenshot({ path: shot }).catch(() => {});
    console.error(`✖ ${name}: ${error.message.split('\n')[0]} (screenshot: ${shot})`);
    break;
  }
}
// Ignored: the demo API has no Realtime, and Flutter's web engine throws inside
// SemanticsTextEditingStrategy when typing with the accessibility tree forced on (test-only).
const appErrors = errors.filter((e) => !/WebSocket|realtime|SemanticsTextEditingStrategy/i.test(e));
if (appErrors.length) console.warn(`Page errors:\n  ${appErrors.join('\n  ')}`);
await browser.close();
process.exitCode = failed ? 1 : 0;
