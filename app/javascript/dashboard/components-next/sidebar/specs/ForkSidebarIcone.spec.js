import { mount } from '@vue/test-utils';
import { defineComponent, h, nextTick, ref } from 'vue';
import ForkSidebarIcone from '../fork/ForkSidebarIcone.vue';
import { temaDoMenu } from '../fork/tema';

// Menu recolhido (#1617): dica de verdade (~300 ms, mouse ou foco, Esc fecha) e contagem no nome acessível.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores = {}) =>
      chave === 'FORK_SIDEBAR.ROTULO_COM_EXTRA'
        ? `${valores.item}, ${valores.extra}`
        : `${valores.count} novas`,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('../provider', () => ({
  usePopoverState: () => ({
    activePopover: ref(null),
    setActivePopover: vi.fn(),
    closeActivePopover: vi.fn(),
    scheduleClose: vi.fn(),
    cancelClose: vi.fn(),
  }),
  useSidebarContext: () => ({}),
}));

const RouterLink = defineComponent({
  props: { to: { type: Object, required: true } },
  setup(props, { slots, attrs }) {
    return () =>
      h('a', { ...attrs, href: `/${props.to.name}` }, slots.default?.());
  },
});

const montar = () =>
  mount(ForkSidebarIcone, {
    props: {
      item: {
        name: 'Inbox',
        label: 'Notificações',
        icon: 'i-lucide-bell',
        to: { name: 'inbox_view' },
      },
      tema: temaDoMenu(false),
      contagem: 3,
    },
    attachTo: document.body,
    global: { components: { RouterLink } },
  });

describe('ForkSidebarIcone', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  it('nome acessível com a contagem e dica ligada por aria-describedby', () => {
    const wrapper = montar();
    const link = wrapper.find('a');
    expect(link.attributes('aria-label')).toBe('Notificações, 3 novas');
    const dica = document.getElementById(link.attributes('aria-describedby'));
    expect(dica.getAttribute('role')).toBe('tooltip');
    expect(dica.textContent.trim()).toBe('Notificações, 3 novas');
  });

  it('a dica aparece depois de 300 ms no foco e some com Esc', async () => {
    const wrapper = montar();
    const link = wrapper.find('a');
    const dica = () =>
      document.getElementById(link.attributes('aria-describedby'));
    await link.trigger('focus');
    vi.advanceTimersByTime(200);
    await nextTick();
    expect(dica().className).toContain('invisible');
    vi.advanceTimersByTime(150);
    await nextTick();
    expect(dica().className).not.toContain('invisible');
    await link.trigger('keydown', { key: 'Escape' });
    expect(dica().className).toContain('invisible');
  });

  it('passar o mouse também mostra a dica', async () => {
    const wrapper = montar();
    await wrapper.find('li').trigger('mouseenter');
    vi.advanceTimersByTime(350);
    await nextTick();
    const id = wrapper.find('a').attributes('aria-describedby');
    expect(document.getElementById(id).className).not.toContain('invisible');
  });
});
