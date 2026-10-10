import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import DialogoAcao from '../../components/pagina/DialogoAcao.vue';
import MaisOpcoes from '../../components/pagina/MaisOpcoes.vue';
import AgenteSemana from '../../components/pagina/AgenteSemana.vue';
import GavetaConversas from '../../components/pagina/GavetaConversas.vue';

// O Dialog do produto e a gaveta usam o TeleportWithDirection, que lê a direção do texto na store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: rota => ({
      href: `/app/${rota.name}/${rota.params?.conversation_id || ''}`,
    }),
  }),
}));
const agentesApi = vi.hoisted(() => ({ analyticsConversations: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: agentesApi }));

const tecla = (alvo, key) =>
  alvo.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));

describe('DialogoAcao', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function fechar() {
      this.removeAttribute('open');
    });
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  const montar = props =>
    mount(DialogoAcao, {
      attachTo: document.body,
      props: {
        titulo: 'Parar Bia?',
        texto: 'As conversas novas vão direto para a equipe.',
        confirmar: 'Parar de atender',
        erroTitulo: 'Não deu para parar agora.',
        erroGarantia: 'Bia continua atendendo.',
        ...props,
      },
    });

  it('runs the action with the AA buttons, waits and closes on success', async () => {
    let terminar;
    const executar = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const wrapper = montar({ executar, rotuloCarregando: 'Parando…' });
    wrapper.vm.abrir();
    await nextTick();

    const confirmar = document.querySelector('[data-confirmar]');
    expect(confirmar.className).toContain('bg-n-blue-11');
    expect(confirmar.className).not.toContain('bg-n-brand');
    confirmar.click();
    await nextTick();
    expect(executar).toHaveBeenCalledTimes(1);
    expect(document.querySelector('[data-confirmar]').textContent).toContain(
      'Parando…'
    );

    terminar();
    await flushPromises();
    expect(wrapper.emitted('confirmado')).toHaveLength(1);
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows the error in place, with one way out', async () => {
    const executar = vi
      .fn()
      .mockRejectedValueOnce(new Error('500'))
      .mockResolvedValueOnce();
    const wrapper = montar({ executar });
    wrapper.vm.abrir();
    await nextTick();
    document.querySelector('[data-confirmar]').click();
    await flushPromises();

    const erro = document.querySelector('[data-erro]');
    expect(erro.textContent).toContain('Não deu para parar agora.');
    expect(erro.textContent).toContain('Bia continua atendendo.');
    expect(document.querySelector('[data-confirmar]')).toBeNull();
    expect(wrapper.emitted('confirmado')).toBeUndefined();

    erro.querySelector('button').click();
    await flushPromises();
    expect(executar).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('confirmado')).toHaveLength(1);
    wrapper.unmount();
  });

  it('only confirms when there is nothing to run', async () => {
    const wrapper = montar({ executar: null });
    wrapper.vm.abrir();
    await nextTick();
    document.querySelector('[data-confirmar]').click();
    await flushPromises();
    expect(wrapper.emitted('confirmado')).toHaveLength(1);
    wrapper.unmount();
  });

  it('puts the danger color only on destructive actions', async () => {
    const wrapper = montar({ variante: 'perigo' });
    wrapper.vm.abrir();
    await nextTick();
    expect(document.querySelector('[data-confirmar]').className).toContain(
      'bg-n-ruby-11'
    );
    wrapper.unmount();
  });

  it('puts an action with no way back in an amber warning (T14)', async () => {
    const wrapper = montar({ variante: 'aviso', executar: null });
    wrapper.vm.abrir();
    await nextTick();
    const aviso = document.querySelector('[data-aviso]');
    expect(aviso.className).toContain('bg-n-amber-2');
    expect(aviso.querySelector('.i-lucide-triangle-alert')).not.toBeNull();
    expect(aviso.textContent).toContain('As conversas novas');
    expect(document.querySelector('[data-confirmar]').className).toContain(
      'bg-[#8A4F00]'
    );
    wrapper.unmount();
  });
});

describe('MaisOpcoes', () => {
  const ITENS = [
    { chave: 'foto', texto: 'Foto e nome', icone: 'i-lucide-image' },
    { chave: 'versoes', texto: 'Jeitos anteriores de responder' },
    { chave: 'excluir', texto: 'Excluir agente', perigo: true, separar: true },
  ];

  const montar = () =>
    mount(MaisOpcoes, {
      attachTo: document.body,
      props: { rotulo: 'Mais opções', itens: ITENS },
    });

  it('is a labelled menu button with 44px items', async () => {
    const wrapper = montar();
    const botao = wrapper.get('[data-mais]');
    expect(botao.text()).toBe('Mais opções');
    expect(botao.attributes('aria-haspopup')).toBe('menu');
    expect(botao.classes()).toContain('min-h-11');

    await botao.trigger('click');
    await nextTick();
    expect(botao.attributes('aria-expanded')).toBe('true');
    const itens = wrapper.findAll('[role="menuitem"]');
    expect(itens.map(item => item.text())).toEqual(ITENS.map(i => i.texto));
    itens.forEach(item => expect(item.classes()).toContain('min-h-11'));
    expect(wrapper.find('[role="separator"]').exists()).toBe(true);
    expect(document.activeElement).toBe(itens[0].element);
    wrapper.unmount();
  });

  it('walks with the arrows, Home and End, and Esc gives focus back', async () => {
    const wrapper = montar();
    await wrapper.get('[data-mais]').trigger('click');
    await nextTick();
    const menu = wrapper.get('[role="menu"]').element;
    const itens = wrapper
      .findAll('[role="menuitem"]')
      .map(item => item.element);

    tecla(menu, 'ArrowDown');
    expect(document.activeElement).toBe(itens[1]);
    tecla(menu, 'End');
    expect(document.activeElement).toBe(itens[2]);
    tecla(menu, 'ArrowDown');
    expect(document.activeElement).toBe(itens[0]);
    tecla(menu, 'ArrowUp');
    expect(document.activeElement).toBe(itens[2]);
    tecla(menu, 'Home');
    expect(document.activeElement).toBe(itens[0]);

    tecla(menu, 'Escape');
    await nextTick();
    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('[data-mais]').element);
    wrapper.unmount();
  });

  it('gives focus back to the button before telling which item was chosen', async () => {
    const wrapper = montar();
    await wrapper.get('[data-mais]').trigger('click');
    await nextTick();
    await wrapper.get('[data-item="excluir"]').trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([['excluir']]);
    expect(document.activeElement).toBe(wrapper.get('[data-mais]').element);
    wrapper.unmount();
  });
});

describe('AgenteSemana', () => {
  const montar = props =>
    mount(AgenteSemana, { props: { nome: 'Bia', ...props } });

  it('hides the whole row when the week numbers could not be read', () => {
    expect(montar({ numeros: null }).html()).toBe('<!--v-if-->');
  });

  it('says the numbers show up later when there is nothing this week', () => {
    const wrapper = montar({ numeros: { respondidas: 0, passadas: 0 } });
    expect(wrapper.find('[data-semana-vazia]').text()).toContain(
      'AGENTS.JORNADA.PAGINA.SEMANA.VAZIA'
    );
    expect(wrapper.find('[data-numero]').exists()).toBe(false);
  });

  it('shows two light cards, with no percentage', () => {
    const wrapper = montar({ numeros: { respondidas: 1234, passadas: 3 } });
    const cartoes = wrapper.findAll('[data-numero]');
    expect(cartoes).toHaveLength(2);
    expect(cartoes[0].text()).toContain('1,234');
    expect(cartoes[1].text()).toContain('3');
    expect(wrapper.text()).not.toContain('%');
    expect(cartoes[0].element.tagName).toBe('DIV');
  });

  it('opens the conversations of the week for whoever manages', async () => {
    const wrapper = montar({
      numeros: { respondidas: 4, passadas: 1 },
      podeAbrir: true,
    });
    const passadas = wrapper.get('[data-numero="passadas"]');
    expect(passadas.element.tagName).toBe('BUTTON');
    await passadas.trigger('click');
    expect(wrapper.emitted('abrir')).toEqual([['passadas']]);
  });
});

describe('GavetaConversas', () => {
  const linha = (id, nome) => ({
    conversation: {
      id,
      display_id: id + 100,
      contact_name: nome,
      last_activity_at: 1760000000,
    },
    occurred_at: 1760000000,
  });

  beforeEach(() => {
    agentesApi.analyticsConversations.mockReset();
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('lists the answered conversations and switches to the handed ones', async () => {
    agentesApi.analyticsConversations
      .mockResolvedValueOnce({
        data: { payload: [linha(1, 'Beatriz')], meta: { has_more: true } },
      })
      .mockResolvedValueOnce({ data: { payload: [], meta: {} } });
    const wrapper = mount(GavetaConversas, {
      attachTo: document.body,
      props: { agentId: 7, aba: 'respondidas' },
    });
    await flushPromises();

    expect(agentesApi.analyticsConversations).toHaveBeenCalledWith(7, {
      range: '7d',
      metric: 'handled',
    });
    const linhas = document.querySelectorAll('[data-linha]');
    expect(linhas).toHaveLength(1);
    expect(linhas[0].textContent).toContain('Beatriz');
    expect(linhas[0].querySelector('a').getAttribute('href')).toBe(
      '/app/inbox_conversation/101'
    );
    expect(document.body.textContent).toContain(
      'AGENTS.JORNADA.PAGINA.CONVERSAS.LIMITE'
    );

    document.querySelector('[data-aba="passadas"]').click();
    await flushPromises();
    expect(agentesApi.analyticsConversations).toHaveBeenLastCalledWith(7, {
      range: '7d',
      metric: 'handed_off',
    });
    expect(
      document
        .querySelector('[data-aba="passadas"]')
        .getAttribute('aria-pressed')
    ).toBe('true');
    expect(document.querySelector('[data-vazio]')).not.toBeNull();
    wrapper.unmount();
  });

  it('shows the standard error with a retry', async () => {
    agentesApi.analyticsConversations
      .mockRejectedValueOnce(new Error('500'))
      .mockResolvedValueOnce({ data: { payload: [linha(2, 'Gustavo')] } });
    const wrapper = mount(GavetaConversas, {
      attachTo: document.body,
      props: { agentId: 7, aba: 'passadas' },
    });
    await flushPromises();
    const erro = document.querySelector('[role="alert"]');
    expect(erro.textContent).toContain('AGENTS.JORNADA.PAGINA.CONVERSAS.ERRO');
    erro.querySelector('button').click();
    await flushPromises();
    expect(document.querySelectorAll('[data-linha]')).toHaveLength(1);
    wrapper.unmount();
  });
});
