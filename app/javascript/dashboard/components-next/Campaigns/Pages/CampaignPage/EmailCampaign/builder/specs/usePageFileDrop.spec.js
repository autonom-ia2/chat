import { createPageFileDrop } from '../composables/usePageFileDrop';
import {
  DRAG_IDLE_MS,
  fileDragActive,
  noteFileDrag,
} from '../composables/fileDragState';
import { dropFilesAtEnd } from '../composables/useImageDrop';

vi.mock('../composables/useImageDrop', () => ({
  dropFilesAtEnd: vi.fn(() => true),
}));

const photo = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });
const withFiles = (files = [photo]) => ({ types: ['Files'], files });
const withText = () => ({ types: ['text/plain'], files: [] });
const dragEvent = (name, dt) => {
  const event = new Event(name, { cancelable: true });
  Object.defineProperty(event, 'dataTransfer', { value: dt });
  return event;
};

describe('file dropped on the editor page outside the canvas (#2908)', () => {
  let target;
  let pageDrop;
  let editorOpen;
  const onNotReady = vi.fn();

  beforeEach(() => {
    target = new EventTarget();
    editorOpen = true;
    onNotReady.mockReset();
    dropFilesAtEnd.mockReset();
    dropFilesAtEnd.mockReturnValue(true);
    pageDrop = createPageFileDrop({
      target,
      isEditorOpen: () => editorOpen,
      onNotReady,
    });
    pageDrop.attach();
  });
  afterEach(() => pageDrop.detach());

  it('never lets the browser open a dragged file, and shows the drop area', () => {
    const over = dragEvent('dragover', withFiles());
    const drop = dragEvent('drop', withFiles());

    target.dispatchEvent(over);
    expect(fileDragActive.value).toBe(true);
    target.dispatchEvent(drop);

    expect(over.defaultPrevented).toBe(true);
    expect(drop.defaultPrevented).toBe(true);
    expect(fileDragActive.value).toBe(false);
  });

  it('leaves drags without files (text, links) to the page', () => {
    const over = dragEvent('dragover', withText());
    const drop = dragEvent('drop', withText());

    target.dispatchEvent(over);
    target.dispatchEvent(drop);

    expect(over.defaultPrevented).toBe(false);
    expect(drop.defaultPrevented).toBe(false);
    expect(dropFilesAtEnd).not.toHaveBeenCalled();
  });

  it('with the editor open, sends the files to the end of the e-mail', () => {
    target.dispatchEvent(dragEvent('drop', withFiles()));

    expect(dropFilesAtEnd).toHaveBeenCalledWith([photo]);
    expect(onNotReady).not.toHaveBeenCalled();
  });

  it('on the "how to start" screen, decides nothing and says what to do first', () => {
    editorOpen = false;
    const drop = dragEvent('drop', withFiles());

    target.dispatchEvent(drop);

    expect(drop.defaultPrevented).toBe(true);
    expect(dropFilesAtEnd).not.toHaveBeenCalled();
    expect(onNotReady).toHaveBeenCalledTimes(1);
  });

  it('says what to do first when no canvas is attached yet', () => {
    dropFilesAtEnd.mockReturnValue(false);

    target.dispatchEvent(dragEvent('drop', withFiles()));

    expect(onNotReady).toHaveBeenCalledTimes(1);
  });

  it('does not take a drop another drop area of the page already handled', () => {
    const drop = dragEvent('drop', withFiles());
    drop.preventDefault();

    target.dispatchEvent(drop);

    expect(dropFilesAtEnd).not.toHaveBeenCalled();
    expect(onNotReady).not.toHaveBeenCalled();
  });

  it('stops listening when the page leaves the screen', () => {
    pageDrop.detach();
    const drop = dragEvent('drop', withFiles());

    target.dispatchEvent(drop);

    expect(drop.defaultPrevented).toBe(false);
    expect(dropFilesAtEnd).not.toHaveBeenCalled();
  });
});

describe('drop area state', () => {
  it('ends a moment after the last dragover (no flicker between elements)', () => {
    vi.useFakeTimers();
    noteFileDrag(withFiles());
    vi.advanceTimersByTime(DRAG_IDLE_MS - 50);
    noteFileDrag(withFiles());
    vi.advanceTimersByTime(DRAG_IDLE_MS - 50);

    expect(fileDragActive.value).toBe(true);
    vi.advanceTimersByTime(100);
    expect(fileDragActive.value).toBe(false);
    vi.useRealTimers();
  });
});
