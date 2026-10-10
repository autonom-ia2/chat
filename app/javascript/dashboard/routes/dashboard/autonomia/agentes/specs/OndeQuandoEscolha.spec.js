import { mount } from '@vue/test-utils';
import OndeQuandoEscolha from '../components/OndeQuandoEscolha.vue';
import { trocaNoCanal } from '../utils/canais';

const permissoes = vi.hoisted(() => ({ quemRecebe: true }));
vi.mock('../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
      podeEscolherQuemRecebe: computed(() => permissoes.quemRecebe),
    }),
  };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));

const canais = [
  { inbox_id: 10, name: 'WhatsApp da Loja', occupied_by: null },
  {
    inbox_id: 11,
    name: 'WhatsApp do Centro',
    occupied_by: {
      kind: 'agent',
      agent_id: 9,
      agent_name: 'Bia',
      operating: true,
    },
  },
  { inbox_id: 12, name: 'Instagram', occupied_by: { kind: 'external' } },
  {
    inbox_id: 13,
    name: 'Site',
    occupied_by: { kind: 'agent', agent_id: 5, agent_name: 'Duda' },
  },
];

const montar = props =>
  mount(OndeQuandoEscolha, {
    props: {
      canais,
      agenteId: 5,
      nome: 'Duda',
      onde: 10,
      quando: 'always',
      ...props,
    },
    attachTo: document.body,
  });

const grupo = (wrapper, rotulo) =>
  wrapper
    .findAll('[role="radiogroup"]')
    .find(g => g.attributes('aria-label') === rotulo);
const opcoes = (wrapper, rotulo) =>
  grupo(wrapper, rotulo).findAll('[role="radio"]');
const ONDE = 'AGENTS.JORNADA.ONDE_QUANDO.ONDE';
const QUANDO = 'AGENTS.JORNADA.ONDE_QUANDO.QUANDO';

describe('OndeQuandoEscolha', () => {
  beforeEach(() => {
    permissoes.quemRecebe = true;
  });

  it('never renders a native select', () => {
    const wrapper = montar();
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });

  it('lists free, own, busy and external inboxes as 44 px radio cards', () => {
    const wrapper = montar();
    const onde = opcoes(wrapper, ONDE);

    expect(onde).toHaveLength(4);
    expect(onde.every(o => o.classes().includes('min-h-11'))).toBe(true);
    expect(onde[0].attributes('aria-checked')).toBe('true');
    expect(onde[0].text()).toContain('WhatsApp da Loja');
    expect(onde[1].text()).toContain('AGENTS.JORNADA.ONDE_QUANDO.OCUPADO');
    expect(onde[1].text()).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.OCUPADO_TEXTO'
    );
    expect(onde[2].attributes('aria-disabled')).toBe('true');
    expect(onde[2].text()).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.EXTERNO_TEXTO'
    );
    // O canal que já é deste agente aparece como livre.
    expect(onde[3].text()).toContain('Site');
    expect(onde[3].text()).not.toContain('OCUPADO');
    wrapper.unmount();
  });

  it('does not let the external inbox be chosen', async () => {
    const wrapper = montar();
    await opcoes(wrapper, ONDE)[2].trigger('click');
    expect(wrapper.emitted('update:onde')).toBeUndefined();
    wrapper.unmount();
  });

  it('warns about the swap when a busy inbox is chosen', async () => {
    const wrapper = montar({ onde: 11 });
    expect(wrapper.get('[data-troca]').text()).toBe(
      'AGENTS.JORNADA.ONDE_QUANDO.TROCA'
    );
    wrapper.unmount();

    const livre = montar({ onde: 10 });
    expect(livre.find('[data-troca]').exists()).toBe(false);
    livre.unmount();
  });

  it('moves with the arrow keys, skipping the disabled option', async () => {
    const wrapper = montar({ onde: 11 });
    const onde = opcoes(wrapper, ONDE);
    expect(onde[1].attributes('tabindex')).toBe('0');
    expect(onde[0].attributes('tabindex')).toBe('-1');

    await onde[1].trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.emitted('update:onde')).toEqual([[13]]);
    wrapper.unmount();
  });

  it('shows the inbox hours under "when" and disables them when there are none', async () => {
    const wrapper = montar({
      horarios: { 10: 'seg a sex, 9h às 18h', 11: null },
    });
    let quando = opcoes(wrapper, QUANDO);
    expect(quando.map(o => o.attributes('aria-disabled'))).toEqual([
      undefined,
      undefined,
      undefined,
    ]);
    expect(quando[1].text()).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.DENTRO_TEXTO'
    );

    await wrapper.setProps({ onde: 11 });
    quando = opcoes(wrapper, QUANDO);
    expect(quando[1].attributes('aria-disabled')).toBe('true');
    expect(quando[2].attributes('aria-disabled')).toBe('true');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.ONDE_QUANDO.SEM_HORARIO');
    wrapper.unmount();
  });

  it('keeps the option without hours text when the inbox is unknown', () => {
    const wrapper = montar({ horarios: {} });
    const quando = opcoes(wrapper, QUANDO);
    expect(quando[1].attributes('aria-disabled')).toBeUndefined();
    expect(quando[1].text()).not.toContain('DENTRO_TEXTO');
    wrapper.unmount();
  });

  it('goes back to "always" when the chosen inbox has no hours', async () => {
    const wrapper = montar({
      quando: 'business_hours',
      horarios: { 11: null },
    });
    await opcoes(wrapper, ONDE)[1].trigger('click');
    expect(wrapper.emitted('update:onde')).toEqual([[11]]);
    expect(wrapper.emitted('update:quando')).toEqual([['always']]);
    wrapper.unmount();
  });

  it('says busy inboxes are hidden when the occupation could not be read', () => {
    const wrapper = montar({ semLeitura: true, canais: [canais[0]] });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.ONDE_QUANDO.SEM_LEITURA');
    wrapper.unmount();
  });

  it('says every inbox is taken when none is free', () => {
    const wrapper = montar({ canais: [canais[1], canais[2]], onde: null });
    expect(wrapper.text()).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.TODOS_OCUPADOS'
    );
    wrapper.unmount();
  });

  it('links to Assignment only for whoever can open it', () => {
    const wrapper = montar();
    const link = wrapper.get('[data-quem-recebe]');
    expect(link.attributes('href')).toBe('/app/crm_handoff_settings_index');
    expect(link.attributes('target')).toBe('_blank');
    wrapper.unmount();

    permissoes.quemRecebe = false;
    const semPermissao = montar();
    expect(semPermissao.find('[data-quem-recebe]').exists()).toBe(false);
    expect(semPermissao.text()).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.QUEM_RECEBE_SEM_PERMISSAO'
    );
    semPermissao.unmount();
  });
});

describe('trocaNoCanal', () => {
  it('describes the swap only for an inbox of another agent', () => {
    expect(trocaNoCanal(canais, 11, 5)).toEqual({
      agenteId: 9,
      nome: 'Bia',
      canal: 'WhatsApp do Centro',
    });
    expect(trocaNoCanal(canais, 10, 5)).toBeNull();
    expect(trocaNoCanal(canais, 13, 5)).toBeNull();
    expect(trocaNoCanal(canais, 12, 5)).toBeNull();
  });
});
