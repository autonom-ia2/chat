// Modal focus for the audience side panel (#993, G4): focus moves into the panel on open, Tab and
// Shift+Tab stay inside it, Escape closes it and focus goes back to the element that opened it.
// A native <dialog> opened on top (the delete confirmation) handles its own keys.
import { onBeforeUnmount, onMounted } from 'vue';

const FOCUSABLE = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

export const focusableIn = container =>
  container ? [...container.querySelectorAll(FOCUSABLE)] : [];

const dialogOnTop = () => Boolean(document.querySelector('dialog[open]'));

const wrapTab = (event, container) => {
  const items = focusableIn(container);
  if (!items.length) {
    event.preventDefault();
    container.focus();
    return;
  }
  const first = items[0];
  const last = items[items.length - 1];
  const active = document.activeElement;
  const outside = !container.contains(active);
  if (event.shiftKey && (active === first || outside)) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && (active === last || outside)) {
    event.preventDefault();
    first.focus();
  }
};

export const useModalFocus = ({ container, initial, onClose }) => {
  let trigger = null;

  const onKeydown = event => {
    if (dialogOnTop()) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      onClose();
      return;
    }
    if (event.key === 'Tab') wrapTab(event, container.value);
  };

  onMounted(() => {
    trigger =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    (initial.value || container.value)?.focus();
    document.addEventListener('keydown', onKeydown);
  });

  onBeforeUnmount(() => {
    document.removeEventListener('keydown', onKeydown);
    if (trigger?.isConnected) trigger.focus();
  });
};
