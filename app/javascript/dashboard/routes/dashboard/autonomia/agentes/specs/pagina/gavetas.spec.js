import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import GavetaTestar from '../../components/pagina/GavetaTestar.vue';
import GavetaFotoNome from '../../components/pagina/GavetaFotoNome.vue';
import GavetaVersoes from '../../components/pagina/GavetaVersoes.vue';
import GavetaInstrucoes from '../../components/pagina/GavetaInstrucoes.vue';

const store = vi.hoisted(() => ({ dispatch: vi.fn(), getters: {} }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};
const digitar = async (seletor, valor) => {
  const campo = no(seletor);
  campo.value = valor;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};

const AGENTE = {
  id: 7,
  name: 'Bia',
  agent_type: 'support',
  mode: 'guided',
  has_instruction: true,
  avatar_url: '',
};

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
    this.setAttribute('open', '');
  });
  HTMLDialogElement.prototype.close = vi.fn(function fechar() {
    this.removeAttribute('open');
  });
  global.URL.createObjectURL = vi.fn(() => 'blob:previa');
  global.URL.revokeObjectURL = vi.fn();
});

beforeEach(() => {
  store.dispatch.mockReset();
  alerta.mockReset();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('GavetaTestar (T08)', () => {
  const montar = props =>
    mount(GavetaTestar, {
      attachTo: document.body,
      props: { agente: AGENTE, nome: 'Bia', atendendo: true, ...props },
    });

  it('says nobody receives the messages and sends the question from the page', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Abrimos sim.' });
    const wrapper = montar({ pergunta: 'Vocês abrem no sábado?' });
    await flushPromises();

    expect(document.body.textContent).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.NINGUEM'
    );
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/test',
      expect.objectContaining({ agentId: 7, message: 'Vocês abrem no sábado?' })
    );
    expect(todos('[data-balao]').map(b => b.textContent)).toEqual([
      expect.stringContaining('Vocês abrem no sábado?'),
      expect.stringContaining('Abrimos sim.'),
    ]);
    wrapper.unmount();
  });

  it('warns that a stopped agent can still be tested', async () => {
    const wrapper = montar({ atendendo: false });
    await flushPromises();
    expect(no('[data-parado]').textContent).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.PARADO'
    );
    wrapper.unmount();
  });

  it('asks a ready question from the chips and focuses the field first', async () => {
    store.dispatch.mockResolvedValue({ reply: 'R$ 59,90' });
    const wrapper = montar();
    await flushPromises();
    expect(document.activeElement.tagName).toBe('TEXTAREA');

    const chips = todos('[role="group"] button');
    expect(chips.map(chip => chip.textContent.trim())).toEqual([
      'AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.A',
      'AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.B',
      'AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.C',
    ]);
    chips[0].click();
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('shows the failure, says it does not affect customers and retries', async () => {
    store.dispatch
      .mockRejectedValueOnce(new Error('500'))
      .mockResolvedValueOnce({ reply: 'Oi!' });
    const wrapper = montar({ pergunta: 'Oi' });
    await flushPromises();
    const aviso = no('[data-aviso="falha"]');
    expect(aviso.textContent).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.FALHOU_GARANTIA'
    );
    aviso.querySelector('button').click();
    await flushPromises();
    expect(no('[data-aviso]')).toBeNull();
    expect(todos('[data-balao]')).toHaveLength(2);
    wrapper.unmount();
  });

  it('says the person is offline (not that the agent failed) and retries', async () => {
    store.dispatch
      .mockRejectedValueOnce(
        Object.assign(new Error('Network Error'), { code: 'ERR_NETWORK' })
      )
      .mockResolvedValueOnce({ reply: 'Oi!' });
    const wrapper = montar({ pergunta: 'Oi' });
    await flushPromises();
    const aviso = no('[data-aviso="offline"]');
    expect(aviso.textContent).toContain('AGENTS.JORNADA.ERRO.OFFLINE');
    expect(no('[data-aviso="falha"]')).toBeNull();
    aviso.querySelector('button').click();
    await flushPromises();
    expect(no('[data-aviso]')).toBeNull();
    expect(todos('[data-balao]')).toHaveLength(2);
    wrapper.unmount();
  });

  it('a 422 from the test says the agent does not know enough yet', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('422'), { response: { status: 422 } })
    );
    const wrapper = montar({ pergunta: 'Oi' });
    await flushPromises();
    expect(no('[data-aviso="incompleto"]').textContent).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.INCOMPLETO'
    );
    wrapper.unmount();
  });

  it('offers "Wrong answer?" only to whoever can change by chatting', async () => {
    store.dispatch.mockResolvedValue({
      reply: 'Abrimos sim.',
      handoff: { should: true },
    });
    const sem = montar({ pergunta: 'Oi' });
    await flushPromises();
    expect(no('[data-errado]')).toBeNull();
    expect(no('[data-passaria]')).not.toBeNull();
    sem.unmount();

    const com = montar({ pergunta: 'Oi', podeMudar: true });
    await flushPromises();
    no('[data-errado]').click();
    expect(com.emitted('errado')[0][0]).toEqual({
      pergunta: 'Oi',
      resposta: 'Abrimos sim.',
      passaria: true,
    });
    com.unmount();
  });

  it('clears the test', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Oi!' });
    const wrapper = montar({ pergunta: 'Oi' });
    await flushPromises();
    await clicar('[data-limpar]');
    expect(todos('[data-balao]')).toHaveLength(0);
    expect(no('[data-vazio]')).not.toBeNull();
    wrapper.unmount();
  });

  it('never shows a confidence score', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Oi!', confidence: 0.42 });
    const wrapper = montar({ pergunta: 'Oi' });
    await flushPromises();
    expect(document.body.textContent).not.toContain('%');
    expect(document.body.textContent).not.toContain('0.42');
    wrapper.unmount();
  });
});

describe('GavetaFotoNome (T12)', () => {
  const montar = props =>
    mount(GavetaFotoNome, {
      attachTo: document.body,
      props: {
        agente: { ...AGENTE, avatar_url: 'https://x/foto.png' },
        ...props,
      },
    });

  it('saves only the name, with a partial PATCH', async () => {
    store.dispatch.mockResolvedValue({});
    const wrapper = montar();
    await nextTick();
    expect(document.activeElement).toBe(no('[data-nome]'));
    await digitar('[data-nome]', 'Rosa');
    await clicar('[data-salvar]');

    expect(store.dispatch.mock.calls).toEqual([
      ['autonomiaAgents/update', { id: 7, name: 'Rosa' }],
    ]);
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.FOTO.PRONTO');
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('asks for a name', async () => {
    const wrapper = montar();
    await digitar('[data-nome]', '   ');
    await clicar('[data-salvar]');
    expect(no('[data-erro-nome]').textContent).toContain('NOME_ERRO');
    expect(store.dispatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('removes the photo through the avatar action', async () => {
    store.dispatch.mockResolvedValue({});
    const wrapper = montar();
    await clicar('[data-tirar-foto]');
    await clicar('[data-salvar]');
    expect(store.dispatch.mock.calls).toEqual([
      ['autonomiaAgents/deleteAvatar', 7],
    ]);
    wrapper.unmount();
  });

  it('refuses a photo that is not JPG/PNG up to 5 MB, and uploads a valid one', async () => {
    store.dispatch.mockResolvedValue({});
    const wrapper = montar();
    const seletor = no('[data-seletor]');
    const escolher = arquivo => {
      Object.defineProperty(seletor, 'files', {
        value: [arquivo],
        configurable: true,
      });
      seletor.dispatchEvent(new Event('change'));
    };

    escolher(new File(['x'], 'foto.gif', { type: 'image/gif' }));
    await nextTick();
    expect(no('[data-erro-foto]').textContent).toContain('FOTO_ERRO');

    const boa = new File(['x'], 'foto.png', { type: 'image/png' });
    escolher(boa);
    await nextTick();
    expect(no('[data-erro-foto]')).toBeNull();
    await clicar('[data-salvar]');
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/updateAvatar',
      {
        agentId: 7,
        avatar: boa,
      }
    );
    wrapper.unmount();
  });

  it('starts with the suggested old name and shows the standard error', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const wrapper = montar({ nomeSugerido: 'Bia antiga' });
    expect(no('[data-nome]').value).toBe('Bia antiga');
    await clicar('[data-salvar]');
    expect(no('[data-erro]').textContent).toContain('FOTO.ERRO_GARANTIA');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    wrapper.unmount();
  });
});

describe('GavetaVersoes (T13)', () => {
  const VERSOES = [
    { id: 3, created_at: '2026-10-09T15:42:00Z', reason: 'rollback' },
    { id: 2, created_at: '2026-10-02T09:05:00Z', reason: 'manual_edit' },
    { id: 1, created_at: '2026-09-28T10:00:00Z', reason: 'kb_refresh' },
  ];

  const montar = props =>
    mount(GavetaVersoes, {
      attachTo: document.body,
      props: { agente: AGENTE, nome: 'Bia', podeGerenciar: true, ...props },
    });

  it('shows date, time and the reason phrase, without "In use"', async () => {
    store.dispatch.mockResolvedValue(VERSOES);
    const wrapper = montar();
    await flushPromises();

    const linhas = todos('[data-versao]');
    expect(linhas).toHaveLength(3);
    expect(linhas[0].textContent).toContain('VERSOES.MOTIVO.ROLLBACK');
    expect(linhas[1].textContent).toContain('VERSOES.MOTIVO.MANUAL_EDIT');
    expect(linhas[2].textContent).toContain('VERSOES.MOTIVO.KB_REFRESH');
    expect(linhas[0].textContent).toContain('Oct');
    expect(document.body.textContent).not.toContain('Em uso');
    wrapper.unmount();
  });

  it('goes back to a version after confirming', async () => {
    store.dispatch.mockResolvedValue(VERSOES);
    store.getters['autonomiaAgents/getInstructionVersions'] = VERSOES;
    const wrapper = montar();
    await flushPromises();

    todos('[data-voltar]')[1].click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/restoreInstructionVersion',
      { agentId: 7, versionId: 2 }
    );
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.VERSOES.PRONTO');
    wrapper.unmount();
  });

  it('is read-only for view-only seats and says when there is nothing', async () => {
    store.dispatch.mockResolvedValue([]);
    const vazia = montar({ podeGerenciar: false });
    await flushPromises();
    expect(no('[data-vazio]')).not.toBeNull();
    vazia.unmount();

    store.dispatch.mockResolvedValue(VERSOES);
    const leitura = montar({ podeGerenciar: false });
    await flushPromises();
    expect(no('[data-voltar]')).toBeNull();
    leitura.unmount();
  });

  it('shows the standard error when the list cannot be read', async () => {
    store.dispatch
      .mockRejectedValueOnce(new Error('500'))
      .mockResolvedValueOnce([]);
    const wrapper = montar();
    await flushPromises();
    no('[data-erro-ler] button').click();
    await flushPromises();
    expect(no('[data-vazio]')).not.toBeNull();
    wrapper.unmount();
  });
});

describe('GavetaInstrucoes (T14)', () => {
  const montar = agente =>
    mount(GavetaInstrucoes, {
      attachTo: document.body,
      props: { agente: agente || AGENTE, nome: 'Bia' },
    });

  it('starts empty for a guided agent and never saves an empty text', async () => {
    const wrapper = montar();
    await nextTick();
    expect(no('[data-instrucao]').value).toBe('');
    expect(document.activeElement).toBe(no('[data-instrucao]'));
    // A regra global de textarea (h-16) venceria o rows: a altura vem da própria classe.
    expect(no('[data-instrucao]').className).toContain('h-auto');
    expect(no('[data-instrucao]').className).toContain('min-h-[22rem]');
    await clicar('[data-salvar]');
    expect(no('[data-vazio]').textContent).toContain('INSTRUCOES.VAZIO');
    expect(store.dispatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('saves mode and instruction together in one PATCH', async () => {
    store.dispatch.mockResolvedValue({});
    const wrapper = montar();
    await digitar('[data-instrucao]', 'Responda com frases curtas.');
    await clicar('[data-salvar]');
    expect(store.dispatch.mock.calls).toEqual([
      [
        'autonomiaAgents/update',
        { id: 7, mode: 'manual', instruction: 'Responda com frases curtas.' },
      ],
    ]);
    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.PAGINA.INSTRUCOES.SALVO'
    );
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('closing without saving writes nothing', async () => {
    const wrapper = montar();
    await digitar('[data-instrucao]', 'Texto');
    no('[data-fechar]').click();
    await nextTick();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    expect(store.dispatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('opens the written text of a manual agent and shows the error in place', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const wrapper = montar({
      ...AGENTE,
      mode: 'manual',
      instruction: 'Atenda bem.',
    });
    expect(no('[data-instrucao]').value).toBe('Atenda bem.');
    await clicar('[data-salvar]');
    expect(no('[data-erro]').textContent).toContain('INSTRUCOES.ERRO_GARANTIA');
    expect(no('[data-salvar]')).toBeNull();
    wrapper.unmount();
  });
});
