import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import MudarConversando from '../../components/pagina/MudarConversando.vue';

// T11 · Mudar conversando: a mesma conversa do Construtor (store autonomiaBuildThreads, que guarda uma
// conversa só), ideias que preenchem o campo, aviso de nome novo e poll parado ao sair.
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  commit: vi.fn(),
  state: null,
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state?.[nome] ?? false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const imagens = vi.hoisted(() => ({ upload: vi.fn() }));
vi.mock('dashboard/api/autonomia/builderImages', () => ({ default: imagens }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const ESTADO = 'autonomiaBuildThreads/';

const AGENTE = {
  id: 7,
  name: 'Bia',
  tone: 'amigavel',
  agent_type: 'support',
  has_instruction: true,
};

const preparar = () => {
  store.state = reactive({
    [`${ESTADO}getMessages`]: [],
    [`${ESTADO}getStatus`]: null,
    [`${ESTADO}getError`]: null,
    [`${ESTADO}getUIFlags`]: { sending: false, creating: false },
    [`${ESTADO}getThread`]: null,
    [`${ESTADO}getAgent`]: null,
  });
  store.dispatch.mockImplementation(async acao => {
    if (acao === `${ESTADO}start`) {
      store.state[`${ESTADO}getThread`] = { id: 55 };
    }
    return null;
  });
};

const montar = props =>
  mount(MudarConversando, {
    attachTo: document.body,
    props: { agente: AGENTE, ...props },
  });

const escrever = async texto => {
  const campo = no('form textarea');
  campo.value = texto;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};

const enviar = async () => {
  no('[data-enviar]').closest('form').dispatchEvent(new Event('submit'));
  await flushPromises();
};

describe('MudarConversando', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function fechar() {
      this.removeAttribute('open');
    });
  });

  beforeEach(() => {
    store.dispatch.mockReset();
    store.commit.mockReset();
    preparar();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('starts clean: stops the old poll and resets the single conversation, without opening one', async () => {
    const wrapper = montar();
    await nextTick();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
    expect(store.dispatch).not.toHaveBeenCalledWith(
      `${ESTADO}start`,
      expect.anything()
    );
    expect(no('[data-abertura]').textContent).toContain('MUDAR_VISTA.ABERTURA');
    wrapper.unmount();
  });

  it('cleans up again when the first message comes back after leaving', async () => {
    let soltar;
    store.dispatch.mockImplementation(acao =>
      acao === `${ESTADO}start`
        ? new Promise(resolve => {
            soltar = resolve;
          })
        : Promise.resolve(null)
    );
    const wrapper = montar();
    await escrever('Mais formal');
    await enviar();
    wrapper.unmount();
    store.dispatch.mockClear();
    store.commit.mockClear();

    soltar(null);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
  });

  it('fills the field with an idea instead of sending it', async () => {
    const wrapper = montar({ origem: 'jeito' });
    await nextTick();
    const ideias = todos('[data-ideias] button');
    expect(ideias.map(ideia => ideia.textContent.trim())).toEqual([
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.A',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.B',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.C',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.D',
    ]);
    ideias[1].click();
    await nextTick();
    expect(no('form textarea').value).toBe(
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.B'
    );
    expect(store.dispatch).not.toHaveBeenCalledWith(
      `${ESTADO}start`,
      expect.anything()
    );
    wrapper.unmount();
  });

  it('opens the conversation on the first message and continues it on the next', async () => {
    const wrapper = montar();
    await escrever('Mais formal');
    await enviar();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}start`, {
      agentId: 7,
      type: 'support',
      message: 'Mais formal',
      image_signed_ids: [],
    });

    await escrever('Sim');
    await enviar();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}send`, {
      threadId: 55,
      content: 'Sim',
      extra: { image_signed_ids: [] },
    });
    wrapper.unmount();
  });

  it('shows the turns, thinking and the standard error with a retry', async () => {
    store.state[`${ESTADO}getMessages`] = [
      { role: 'user', content: 'Mudar preços' },
      { role: 'assistant', content: 'O que mudou?' },
    ];
    store.state[`${ESTADO}getStatus`] = 'processing';
    const wrapper = montar();
    await nextTick();
    expect(todos('[data-mensagem]').map(m => m.dataset.mensagem)).toEqual([
      'user',
      'assistant',
    ]);
    expect(no('[data-pensando]')).not.toBeNull();
    expect(no('[data-ideias]')).toBeNull();

    store.state[`${ESTADO}getStatus`] = 'failed';
    store.state[`${ESTADO}getError`] = 'failed';
    store.state[`${ESTADO}getThread`] = { id: 55 };
    await nextTick();
    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('MUDAR_VISTA.ERRO_GARANTIA');
    erro.querySelector('button').click();
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}retry`, {
      threadId: 55,
    });
    wrapper.unmount();
  });

  it('tells the new name with a way back, and that the way of talking changed', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getAgent`] = {
      ...AGENTE,
      name: 'Rosa',
      tone: 'formal',
    };
    await nextTick();

    expect(no('[data-feito]').textContent).toContain('MUDAR_VISTA.FEITO');
    expect(no('[data-nome-novo]').textContent).toContain(
      'MUDAR_VISTA.NOME_NOVO'
    );
    expect(no('[data-jeito-novo]')).not.toBeNull();
    expect(no('[data-atualizado]')).not.toBeNull();
    no('[data-voltar-nome]').click();
    expect(wrapper.emitted('voltarNome')).toEqual([['Bia']]);
    wrapper.unmount();
  });

  it('says nothing about the name when it did not change', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getAgent`] = { ...AGENTE };
    await nextTick();
    expect(no('[data-feito]')).not.toBeNull();
    expect(no('[data-nome-novo]')).toBeNull();
    expect(no('[data-jeito-novo]')).toBeNull();
    wrapper.unmount();
  });

  it('comes from the test with the question and the answer in the field and on the phone', async () => {
    const wrapper = montar({
      origem: 'teste',
      testeInicial: { pergunta: 'Vocês abrem no sábado?', resposta: 'Abrimos' },
    });
    await nextTick();
    expect(no('form textarea').value).toBe(
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.RASCUNHO_ERRADO'
    );
    expect(no('[data-ideias]')).toBeNull();
    expect(todos('[data-balao]').length).toBeGreaterThan(0);
    wrapper.unmount();
  });

  it('asks before leaving in the middle of a conversation', async () => {
    store.state[`${ESTADO}getMessages`] = [{ role: 'user', content: 'Oi' }];
    const wrapper = montar();
    await nextTick();
    no('[data-voltar]').click();
    await nextTick();
    expect(wrapper.emitted('sair')).toBeUndefined();
    expect(document.querySelector('dialog').textContent).toContain(
      'MUDAR_VISTA.SAIR_TITULO'
    );
    no('dialog [data-confirmar]').click();
    await flushPromises();
    expect(wrapper.emitted('sair')).toHaveLength(1);
    wrapper.unmount();
  });

  it('leaves right away when nothing was said, and stops the poll on the way out', async () => {
    const wrapper = montar();
    await nextTick();
    no('[data-pronto]').click();
    expect(wrapper.emitted('sair')).toHaveLength(1);
    store.dispatch.mockClear();
    store.commit.mockClear();
    wrapper.unmount();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
  });
});
