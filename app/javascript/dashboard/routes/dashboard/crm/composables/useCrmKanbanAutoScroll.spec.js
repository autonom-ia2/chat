import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import {
  scrollKanbanAtPointer,
  useCrmKanbanAutoScroll,
} from './useCrmKanbanAutoScroll';

const rect = (left, top, width, height) => ({
  left,
  top,
  right: left + width,
  bottom: top + height,
  width,
  height,
});
const makeBoard = value => {
  const scale = value / 100;
  const list = {
    scrollTop: 0,
    clientHeight: 500 / scale,
    scrollHeight: 1600,
    getBoundingClientRect: () => rect(100, 130, 300 * scale, 500),
  };
  const board = {
    scrollLeft: 0,
    clientWidth: 1000 / scale,
    scrollWidth: 2400,
    getBoundingClientRect: () => rect(100, 100, 1000, 600),
    querySelectorAll: () => [list],
  };
  return { board, list };
};

const cases = [70, 80, 87, 90, 100, 110, 117, 120, 130];
describe('Zoom-aware Kanban edge scrolling', () => {
  it.each(cases)(
    'uses layout scroll limits and physical pointer coordinates at %i',
    value => {
      const { board } = makeBoard(value);
      scrollKanbanAtPointer(board, { x: 1095, y: 400 }, value, 16);
      expect(board.scrollLeft).toBeCloseTo(10 / (value / 100));
      // Continue beyond the wrong rect.width + scrollLeft >= scrollWidth cutoff.
      board.scrollLeft = board.scrollWidth - board.clientWidth - 3;
      scrollKanbanAtPointer(board, { x: 1095, y: 400 }, value, 16);
      expect(board.scrollLeft).toBeCloseTo(
        board.scrollWidth - board.clientWidth
      );
      scrollKanbanAtPointer(board, { x: 105, y: 400 }, value, 16);
      expect(board.scrollLeft).toBeLessThan(
        board.scrollWidth - board.clientWidth
      );
    }
  );

  it.each(cases)('preserves negative RTL scroll offsets at %i', value => {
    const { board } = makeBoard(value);
    board.scrollLeft = -400;
    scrollKanbanAtPointer(board, { x: 105, y: 400 }, value, 16, true);
    expect(board.scrollLeft).toBeCloseTo(-400 - 10 / (value / 100));
    scrollKanbanAtPointer(board, { x: 1095, y: 400 }, value, 16, true);
    expect(board.scrollLeft).toBeCloseTo(-400);
    board.scrollLeft = -board.scrollWidth + board.clientWidth + 3;
    scrollKanbanAtPointer(board, { x: 105, y: 400 }, value, 16, true);
    expect(board.scrollLeft).toBeCloseTo(
      -board.scrollWidth + board.clientWidth
    );
    board.scrollLeft = -2;
    scrollKanbanAtPointer(board, { x: 1095, y: 400 }, value, 16, true);
    expect(board.scrollLeft).toBeCloseTo(0);
  });

  it.each(cases)('scrolls the hovered column vertically at %i', value => {
    const { board, list } = makeBoard(value);
    scrollKanbanAtPointer(board, { x: 150, y: 625 }, value, 16);
    expect(list.scrollTop).toBeCloseTo(10 / (value / 100));
    expect(board.scrollLeft).toBe(0);
    scrollKanbanAtPointer(board, { x: 150, y: 135 }, value, 16);
    expect(list.scrollTop).toBe(0);
  });

  it.each([
    { x: 600, y: 400 },
    { x: 1105, y: 400 },
    { x: 50, y: 400 },
    { x: 105, y: 80 },
  ])('does not scroll outside the board or away from edges: %j', point => {
    const { board, list } = makeBoard(130);
    scrollKanbanAtPointer(board, point, 130, 16);
    expect(board.scrollLeft).toBe(0);
    expect(list.scrollTop).toBe(0);
  });

  it('does not start a frame loop before drag and removes it on stop/unmount', () => {
    const request = vi
      .spyOn(window, 'requestAnimationFrame')
      .mockReturnValue(42);
    const cancel = vi
      .spyOn(window, 'cancelAnimationFrame')
      .mockImplementation(() => {});
    let controls;
    const wrapper = mount(
      defineComponent({
        setup() {
          controls = useCrmKanbanAutoScroll(
            ref(makeBoard(130).board),
            ref(130)
          );
          return () => h('div');
        },
      })
    );
    expect(request).not.toHaveBeenCalled();
    controls.start({ originalEvent: { clientX: 1095, clientY: 400 } });
    expect(request).toHaveBeenCalledOnce();
    controls.stop();
    expect(cancel).toHaveBeenCalledWith(42);
    controls.start();
    wrapper.unmount();
    expect(cancel).toHaveBeenCalledTimes(2);
    request.mockRestore();
    cancel.mockRestore();
  });
});
