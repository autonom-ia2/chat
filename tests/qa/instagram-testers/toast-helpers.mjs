import assert from 'node:assert/strict';

// Executed in Chromium. The marker is an attribute on the REAL component root.
export function readToastEvidence() {
  const bounds = element => {
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return {
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
      width: rect.width,
      height: rect.height,
    };
  };
  return [...document.querySelectorAll('[data-instagram-qa-toasts]')].map(
    container => ({
      text: container.innerText.trim(),
      open: container.matches(':popover-open'),
      rect: bounds(container),
      textRect: bounds(container.querySelector('.text-sm')),
    })
  );
}

export function assertToastEvidence(containers, expectedText, viewport) {
  assert.equal(containers.length, 1, 'Real dashboard snackbar host missing');
  const toast = containers[0];
  assert.equal(
    toast.text,
    expectedText,
    'Unexpected/missing real toast message'
  );
  if (!expectedText) return;
  assert.equal(toast.open, true, 'Real toast popover is closed');
  [toast.rect, toast.textRect].forEach(rect => {
    assert.ok(rect && rect.width > 0 && rect.height > 0, 'Toast is invisible');
    assert.ok(
      rect.left >= 0 &&
        rect.top >= 0 &&
        rect.right <= viewport.width &&
        rect.bottom <= viewport.height,
      'Real toast is outside the viewport'
    );
  });
}
