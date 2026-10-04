import test from 'node:test';
import assert from 'node:assert/strict';
import { assertToastEvidence } from './toast-helpers.mjs';

const viewport = { width: 390, height: 844 };
const rect = {
  left: 16,
  top: 16,
  right: 374,
  bottom: 80,
  width: 358,
  height: 64,
};
const toast = { text: 'Erro traduzido', open: true, rect, textRect: rect };

test('toast evidence requires the exact translated message in the real open popover and viewport', () => {
  assertToastEvidence([toast], 'Erro traduzido', viewport);
  assert.throws(() => assertToastEvidence([], 'Erro traduzido', viewport));
  assert.throws(() => assertToastEvidence([toast], 'Outra mensagem', viewport));
  assert.throws(() =>
    assertToastEvidence([{ ...toast, open: false }], toast.text, viewport)
  );
  assert.throws(() =>
    assertToastEvidence([{ ...toast, textRect: null }], toast.text, viewport)
  );
  assert.throws(() =>
    assertToastEvidence(
      [{ ...toast, rect: { ...rect, bottom: 845 } }],
      toast.text,
      viewport
    )
  );
});

test('mounting the global snackbar does not permit unsolicited toast messages in other cases', () => {
  assertToastEvidence([{ text: '', open: false }], '', viewport);
  assert.throws(() => assertToastEvidence([toast], '', viewport));
});
