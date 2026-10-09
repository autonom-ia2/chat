import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { installDomHelpers } from './browser-helpers.mjs';

test('keyboard expectations include offscreen/negative-tabindex actions but exclude truly hidden ancestors and closed details', () => {
  const dom = new JSDOM(
    `<body>
    <button id="visible">Visible</button><button id="offscreen">Below viewport</button>
    <button id="negative" tabindex="-1">Broken action</button>
    <details><summary id="summary">Details</summary><summary id="second">Not the first summary</summary><div><button id="closed">Copy</button></div></details>
    <details open><summary>Outer</summary><details><summary id="nested-summary">Inner</summary><button id="nested-closed">Copy</button></details></details>
    <div hidden><button id="hidden">Hidden</button></div>
    <div inert><button id="inert">Inert</button></div>
    <div style="display:none"><button id="display">Display</button></div>
    <div style="visibility:hidden"><button id="visibility">Visibility</button><button id="restored" style="visibility:visible">Restored</button></div>
    <div style="opacity:0"><button id="opacity">Opacity</button></div>
    <button id="zero">Zero size</button>
  </body>`,
    { runScripts: 'outside-only' }
  );
  const { window } = dom;
  // jsdom has no layout. Give even closed-details descendants positive geometry
  // to reproduce the old harness error; this does not claim browser/CSS coverage.
  window.HTMLElement.prototype.getClientRects = function () {
    return this.id === 'zero'
      ? []
      : [{ width: 100, height: 32, y: this.id === 'offscreen' ? 5000 : 0 }];
  };
  window.document.querySelector('[inert]').inert = true;
  window.eval(`(${installDomHelpers.toString()})()`);
  for (const id of [
    'visible',
    'restored',
    'offscreen',
    'negative',
    'summary',
    'nested-summary',
    'zero',
  ]) {
    assert.equal(
      window.__qaDom.isExposed(window.document.getElementById(id)),
      true,
      id
    );
  }
  for (const id of [
    'second',
    'closed',
    'nested-closed',
    'hidden',
    'inert',
    'display',
    'visibility',
    'opacity',
  ]) {
    assert.equal(
      window.__qaDom.isExposed(window.document.getElementById(id)),
      false,
      id
    );
  }
  window.document.querySelector('details').open = true;
  assert.equal(
    window.__qaDom.isExposed(window.document.getElementById('closed')),
    true
  );
  dom.window.close();
});
