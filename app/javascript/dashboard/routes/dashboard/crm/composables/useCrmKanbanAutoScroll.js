import { onScopeDispose, watch } from 'vue';

const EDGE = 30;
const FRAME_MS = 16;
const MAX_FRAME_MS = 32;
const SPEED = 10;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const direction = (point, start, end) =>
  Number(point >= end - EDGE) - Number(point <= start + EDGE);

// Pointer rectangles are physical pixels; scroll extents are CSS layout pixels.
// Sortable 1.x compares the two directly, which can stop scrolling early at >100%.
export function scrollKanbanAtPointer(
  board,
  point,
  zoom,
  elapsed,
  isRtl = false
) {
  if (!board || !point) return;
  const bounds = board.getBoundingClientRect();
  const { x, y } = point;
  if (
    x < bounds.left ||
    x > bounds.right ||
    y < bounds.top ||
    y > bounds.bottom
  )
    return;
  const step =
    (SPEED * clamp(elapsed, 0, MAX_FRAME_MS)) / FRAME_MS / (zoom / 100);
  const horizontal = direction(x, bounds.left, bounds.right);
  if (horizontal) {
    const extent = Math.max(0, board.scrollWidth - board.clientWidth);
    // RTL browsers count from zero at the right edge toward negative offsets.
    board.scrollLeft = clamp(
      board.scrollLeft + horizontal * step,
      isRtl ? -extent : 0,
      isRtl ? 0 : extent
    );
  }
  board.querySelectorAll('[data-kanban-list]').forEach(list => {
    const column = list.getBoundingClientRect();
    const top = Math.max(column.top, bounds.top);
    const bottom = Math.min(column.bottom, bounds.bottom);
    if (x < column.left || x > column.right || y < top || y > bottom) return;
    const vertical = direction(y, top, bottom);
    if (vertical) {
      list.scrollTop = clamp(
        list.scrollTop + vertical * step,
        0,
        Math.max(0, list.scrollHeight - list.clientHeight)
      );
    }
  });
}

const MOVE_EVENTS = ['pointermove', 'mousemove', 'touchmove'];
const END_EVENTS = [
  'pointerup',
  'pointercancel',
  'mouseup',
  'touchend',
  'touchcancel',
];

export function useCrmKanbanAutoScroll(board, zoom) {
  let frame = null;
  let pointer = null;
  let previousTime = 0;
  const updatePointer = event => {
    const source = event?.touches?.[0] || event;
    if (Number.isFinite(source?.clientX) && Number.isFinite(source?.clientY)) {
      pointer = { x: source.clientX, y: source.clientY };
    }
  };
  const stop = () => {
    if (frame !== null) window.cancelAnimationFrame(frame);
    frame = null;
    pointer = null;
    previousTime = 0;
    MOVE_EVENTS.forEach(type =>
      document.removeEventListener(type, updatePointer, true)
    );
    END_EVENTS.forEach(type => document.removeEventListener(type, stop, true));
    window.removeEventListener('blur', stop);
  };
  const tick = timestamp => {
    if (!board.value) {
      stop();
      return;
    }
    scrollKanbanAtPointer(
      board.value,
      pointer,
      zoom.value,
      previousTime ? timestamp - previousTime : FRAME_MS,
      window.getComputedStyle(board.value).direction === 'rtl'
    );
    previousTime = timestamp;
    frame = window.requestAnimationFrame(tick);
  };
  const start = event => {
    stop();
    if (!board.value) return;
    updatePointer(event?.originalEvent);
    MOVE_EVENTS.forEach(type =>
      document.addEventListener(type, updatePointer, {
        capture: true,
        passive: true,
      })
    );
    END_EVENTS.forEach(type => document.addEventListener(type, stop, true));
    window.addEventListener('blur', stop);
    frame = window.requestAnimationFrame(tick);
  };
  watch(board, value => {
    if (!value) stop();
  });
  onScopeDispose(stop);
  return { start, stop };
}
