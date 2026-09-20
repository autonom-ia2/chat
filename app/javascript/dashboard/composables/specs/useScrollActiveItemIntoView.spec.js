import { ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { useScrollActiveItemIntoView } from '../useScrollActiveItemIntoView';

const frames = async (times = 3) => {
  for (let i = 0; i < times; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      requestAnimationFrame(resolve);
    });
  }
  await nextTick();
};

const rect = (top, bottom) => ({ top, bottom });

// Container de 100px de altura; o item ativo é colocado dentro ou fora dele.
const buildDom = ({ activeTop, activeBottom, withActive = true }) => {
  const container = document.createElement('nav');
  container.getBoundingClientRect = () => rect(0, 100);

  if (withActive) {
    const active = document.createElement('a');
    active.className = 'active';
    active.getBoundingClientRect = () => rect(activeTop, activeBottom);
    active.scrollIntoView = vi.fn();
    container.appendChild(active);
  }

  return container;
};

const run = (container, route) => {
  const containerRef = ref(container);
  const routeRef = ref(route);
  // O composable usa watch, que precisa de uma instância ativa.
  mount({
    setup() {
      useScrollActiveItemIntoView(containerRef, () => routeRef.value);
      return () => null;
    },
  });
  return { containerRef, routeRef };
};

describe('useScrollActiveItemIntoView', () => {
  it('scrolls the active item into view when it is below the fold', async () => {
    const container = buildDom({ activeTop: 320, activeBottom: 360 });

    run(container, '/settings/canned-response');
    await frames();

    expect(
      container.querySelector('a.active').scrollIntoView
    ).toHaveBeenCalledWith({ block: 'nearest' });
  });

  it('leaves the list alone when the active item is already visible', async () => {
    const container = buildDom({ activeTop: 20, activeBottom: 40 });

    run(container, '/settings/general');
    await frames();

    expect(
      container.querySelector('a.active').scrollIntoView
    ).not.toHaveBeenCalled();
  });

  it('waits for the group to open before giving up', async () => {
    const container = buildDom({ withActive: false });
    run(container, '/settings/security');
    await frames(2);

    const active = document.createElement('a');
    active.className = 'active';
    active.getBoundingClientRect = () => rect(500, 540);
    active.scrollIntoView = vi.fn();
    container.appendChild(active);
    await frames(4);

    expect(active.scrollIntoView).toHaveBeenCalled();
  });

  it('scrolls again when the route changes', async () => {
    const container = buildDom({ activeTop: 400, activeBottom: 440 });
    const { routeRef } = run(container, '/settings/general');
    await frames();

    const active = container.querySelector('a.active');
    active.scrollIntoView.mockClear();
    routeRef.value = '/settings/labels';
    await frames();

    expect(active.scrollIntoView).toHaveBeenCalled();
  });
});
