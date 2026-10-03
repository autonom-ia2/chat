import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MINIMUM_TEXT_CONTRAST,
  parseComputedColor,
  compositeColor,
  brightnessColor,
  contrastRatio,
  computedAppearance,
} from './visual-helpers.mjs';

const white = parseComputedColor('rgb(255, 255, 255)');

test('sRGB fixtures preserve canonical contrast and alpha composition', () => {
  assert.equal(contrastRatio(white, parseComputedColor('rgb(0 0 0)')), 21);
  assert.equal(contrastRatio(white, white), 1);
  assert.deepEqual(
    compositeColor(parseComputedColor('rgba(0, 0, 0, 0.5)'), white),
    [127.5, 127.5, 127.5, 1]
  );
  assert.deepEqual(
    parseComputedColor('rgb(100% 0% 0% / 50%)'),
    [255, 0, 0, 0.5]
  );
});

test('old solid-button and accepted-title color fixtures fail the 4.5 threshold', () => {
  const oldButton = contrastRatio(
    white,
    parseComputedColor('rgb(39, 129, 246)')
  );
  const oldTitle = contrastRatio(
    parseComputedColor('rgb(0, 133, 115)'),
    parseComputedColor('rgb(247, 247, 247)')
  );
  assert.ok(oldButton > 3.77 && oldButton < 3.79);
  assert.ok(oldTitle > 4.25 && oldTitle < 4.27);
  assert.ok(
    oldButton < MINIMUM_TEXT_CONTRAST && oldTitle < MINIMUM_TEXT_CONTRAST
  );
});

test('corrected light-button fixture passes, while inherited brightness110 fails', () => {
  const background = parseComputedColor('rgb(13, 116, 206)');
  assert.ok(contrastRatio(white, background) >= MINIMUM_TEXT_CONTRAST);
  assert.ok(
    contrastRatio(
      brightnessColor(white, 'brightness(1.1)'),
      brightnessColor(background, 'brightness(1.1)')
    ) < MINIMUM_TEXT_CONTRAST
  );
  assert.deepEqual(brightnessColor(background, 'brightness(100%)'), background);
});

test('unsupported filters/colors and unresolved transparent surfaces fail explicitly', () => {
  assert.throws(() => parseComputedColor('color(display-p3 1 1 1)'));
  assert.throws(() => brightnessColor(white, 'brightness(1) blur(2px)'));
  assert.throws(() => contrastRatio(white, [0, 0, 0, 0]));
});

test('placeholder fixture measures pseudo color and opacity instead of the input foreground', t => {
  const previousWindow = globalThis.window;
  t.after(() => {
    if (previousWindow === undefined) delete globalThis.window;
    else globalThis.window = previousWindow;
  });
  const inputStyle = {
    color: 'rgb(255, 255, 255)',
    backgroundColor: 'rgb(0, 0, 0)',
    backgroundImage: 'none',
    opacity: '1',
    filter: 'none',
  };
  const placeholderStyle = { ...inputStyle, opacity: '0.25' };
  const calls = [];
  globalThis.window = {
    getComputedStyle: (element, pseudo) => {
      calls.push(pseudo);
      return pseudo === '::placeholder' ? placeholderStyle : inputStyle;
    },
  };
  const input = {
    tagName: 'INPUT',
    parentElement: null,
    textContent: '',
    getAttribute: () => '@suaempresa',
  };
  assert.equal(computedAppearance(input).contrast, 21);
  const translucent = computedAppearance(input, '::placeholder');
  assert.ok(translucent.contrast < MINIMUM_TEXT_CONTRAST);
  assert.equal(translucent.pseudoOpacity, 0.25);
  assert.deepEqual(translucent.foreground, [63.75, 63.75, 63.75, 1]);
  placeholderStyle.opacity = '1';
  placeholderStyle.color = 'rgb(128, 131, 141)';
  const colored = computedAppearance(input, '::placeholder');
  assert.equal(
    colored.contrast,
    contrastRatio(
      parseComputedColor(placeholderStyle.color),
      parseComputedColor(inputStyle.backgroundColor)
    )
  );
  assert.equal(colored.color, placeholderStyle.color);
  assert.equal(colored.text, '@suaempresa');
  assert.ok(calls.includes('::placeholder'));
});
