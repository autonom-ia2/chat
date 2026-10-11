import { mount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import SidebarCollapsedPopover from '../SidebarCollapsedPopover.vue';

// Barra lateral recolhida (#1288): no popover do CRM, o subgrupo Agendamento
// também nasce fechado, abre sozinho na tela de um filho e abre no clique.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('../provider', () => ({
  useSidebarContext: () => ({
    isAllowed: () => true,
    sidebarWidth: ref(56),
  }),
}));

const leaf = (name, label) => ({ name, label, to: { name } });

const children = [
  leaf('CRM Kanban', 'Kanban'),
  {
    name: 'CRM Scheduling',
    label: 'Agendamento',
    icon: 'i-lucide-calendar-clock',
    collapsible: true,
    defaultCollapsed: true,
    children: [
      leaf('CRM Calendar', 'Calendário'),
      leaf('CRM Booking', 'Páginas e links'),
    ],
  },
];

const mountPopover = async props => {
  const wrapper = mount(SidebarCollapsedPopover, {
    props: { label: 'CRM', children, ...props },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        Icon: true,
        SidebarSortMenu: true,
        Transition: false,
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
      },
    },
  });
  await nextTick();
  await nextTick();
  return wrapper;
};

const links = wrapper => wrapper.findAll('a').map(link => link.text());

describe('SidebarCollapsedPopover: subgrupo Agendamento', () => {
  it('nasce fechado: só o item solto aparece', async () => {
    const wrapper = await mountPopover();

    expect(links(wrapper)).toEqual(['Kanban']);
  });

  it('abre sozinho quando a tela ativa é o Calendário', async () => {
    const wrapper = await mountPopover({
      activeChild: children[1].children[0],
    });

    expect(links(wrapper)).toEqual(['Kanban', 'Calendário', 'Páginas e links']);
  });

  it('abre no clique do nome do subgrupo', async () => {
    const wrapper = await mountPopover();

    const header = wrapper
      .findAll('button')
      .find(button => button.text() === 'Agendamento');
    await header.trigger('click');

    expect(links(wrapper)).toEqual(['Kanban', 'Calendário', 'Páginas e links']);
  });
});
