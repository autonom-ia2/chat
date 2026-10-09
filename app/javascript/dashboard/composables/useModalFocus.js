import { onBeforeUnmount } from 'vue';

const FOCUSABLE = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

const resolveContainer = container =>
  container && typeof container === 'object' && 'value' in container
    ? container.value
    : container;

export const focusableIn = container => {
  const element = resolveContainer(container);
  return element ? [...element.querySelectorAll(FOCUSABLE)] : [];
};

const dialogOnTop = () => Boolean(document.querySelector('dialog[open]'));

const wrapTab = (event, container) => {
  if (!container) return;

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
  const onContainer = active === container;

  if (event.shiftKey && (active === first || onContainer || outside)) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && (active === last || onContainer || outside)) {
    event.preventDefault();
    first.focus();
  }
};

export const useModalFocus = ({ container }) => {
  let isActive = false;

  const onKeydown = event => {
    if (!isActive || event.key !== 'Tab' || dialogOnTop()) return;
    wrapTab(event, resolveContainer(container));
  };

  const activate = () => {
    if (isActive) return;
    isActive = true;
    document.addEventListener('keydown', onKeydown);
  };

  const deactivate = () => {
    if (!isActive) return;
    isActive = false;
    document.removeEventListener('keydown', onKeydown);
  };

  onBeforeUnmount(deactivate);

  return { activate, deactivate };
};
