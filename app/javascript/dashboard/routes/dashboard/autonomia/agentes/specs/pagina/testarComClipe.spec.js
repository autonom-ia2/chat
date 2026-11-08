import { DOMWrapper, mount, flushPromises } from '@vue/test-utils';
import GavetaTestar from '../../components/pagina/GavetaTestar.vue';
import MaterialLinha from '../../components/pagina/MaterialLinha.vue';

// #1427 — o clipe no Testar da página do agente (mockup 15 a 19). Na Fase 2: foto para todos, lida só no teste; outro
// arquivo só para quem gerencia, e não é lido: "Quer que aprenda com isto?". A cotação e as contas fora da Fase 2 ficam
// como na main (sem clipe). E o "Lendo a página X de N…" da linha do material (mockup 02).
const store = vi.hoisted(() => ({ dispatch: vi.fn(), getters: {} }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => false),
  };
});

const AGENTE = {
  id: 7,
  name: 'Bia',
  agent_type: 'support',
  mode: 'guided',
  has_instruction: true,
};
const COTACAO = { ...AGENTE, agent_type: 'insurance_quote' };
const MB = 1024 * 1024;
const corpo = () => new DOMWrapper(document.body);

// O tamanho vem declarado (sem gerar megabytes no teste).
const arquivo = (nome, type, tamanho) =>
  Object.defineProperty(new File(['x'], nome, { type }), 'size', {
    value: tamanho,
  });
const foto = (nome = 'lanche.png', tamanho = 1) =>
  arquivo(nome, 'image/png', tamanho);
const pdf = (nome = 'cardapio-novo.pdf', tamanho = 1) =>
  arquivo(nome, 'application/pdf', tamanho);

const montar = props =>
  mount(GavetaTestar, {
    attachTo: document.body,
    props: { agente: AGENTE, nome: 'Bia', atendendo: true, ...props },
  });

const anexar = async arquivos => {
  const seletor = corpo().get('input[type="file"]');
  Object.defineProperty(seletor.element, 'files', {
    value: arquivos,
    configurable: true,
  });
  await seletor.trigger('change');
};

const escrever = async texto => {
  await corpo().get('form textarea').setValue(texto);
};

const enviar = async () => {
  await corpo().get('form').trigger('submit');
  await flushPromises();
};

const chamadasDe = acao =>
  store.dispatch.mock.calls.filter(([nome]) => nome === acao);

beforeAll(() => {
  global.URL.createObjectURL = vi.fn(() => 'blob:previa');
  global.URL.revokeObjectURL = vi.fn();
});

beforeEach(() => {
  store.dispatch.mockReset();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('Testar without the clip (as in main)', () => {
  it('has no clip outside the Fase 2', async () => {
    const wrapper = montar({ fase2: false, podeGerenciar: true });
    await flushPromises();

    expect(corpo().find('[data-anexar]').exists()).toBe(false);
    expect(corpo().find('input[type="file"]').exists()).toBe(false);
    expect(corpo().find('form textarea').exists()).toBe(true);
    wrapper.unmount();
  });

  it('has no clip for the quote agent (the Lia), even in the Fase 2', async () => {
    const wrapper = montar({
      agente: COTACAO,
      fase2: true,
      podeGerenciar: true,
    });
    await flushPromises();

    expect(corpo().find('[data-anexar]').exists()).toBe(false);
    wrapper.unmount();
  });
});

describe('Testar with the clip (Fase 2)', () => {
  it('sends the photo with the question, only to the test, and shows it in the customer bubble', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Pela foto, é o X-Salada.' });
    const wrapper = montar({ fase2: true, podeGerenciar: false });
    await flushPromises();

    await anexar([foto()]);
    await enviar();

    await vi.waitFor(() =>
      expect(chamadasDe('autonomiaAgents/test')).toHaveLength(1)
    );
    expect(chamadasDe('autonomiaAgents/test')[0][1]).toEqual(
      expect.objectContaining({
        agentId: 7,
        message: 'AGENTS.JORNADA.CRIAR.CONFIRA.FOTO',
        images: [expect.stringContaining('data:image/png')],
      })
    );
    await flushPromises();
    expect(corpo().find('[data-balao="cliente"] img').exists()).toBe(true);
    expect(corpo().text()).toContain('Pela foto, é o X-Salada.');
    expect(chamadasDe('autonomiaSources/create')).toHaveLength(0);
    wrapper.unmount();
  });

  it('gives whoever only views a photo-only clip: a file never reaches "learn"', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: false });
    await flushPromises();

    expect(corpo().get('input[type="file"]').attributes('accept')).toBe(
      'image/*'
    );
    await anexar([pdf()]);
    await enviar();

    expect(corpo().find('[data-aprender]').exists()).toBe(false);
    expect(store.dispatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('labels the clip "photo or file" for whoever manages', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();

    expect(corpo().get('[data-anexar]').attributes('aria-label')).toBe(
      'AGENTS.JORNADA.PAGINA.TESTE.ANEXAR'
    );
    expect(
      corpo().get('input[type="file"]').attributes('accept')
    ).toBeUndefined();
    wrapper.unmount();
  });

  it('refuses a photo above 5 MB in the browser, without sending it', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: false });
    await flushPromises();

    await anexar([foto('grande.png', 5 * MB + 1)]);
    await escrever('Quanto custa este?');
    await enviar();

    expect(store.dispatch).not.toHaveBeenCalled();
    const aviso = corpo().get('[data-aviso="foto-recusada"]');
    expect(aviso.text()).toContain('AGENTS.JORNADA.PAGINA.SABE.FOTO_GRANDE');
    expect(aviso.find('button').exists()).toBe(false);
    await flushPromises();
    expect(corpo().get('form textarea').element.value).toBe(
      'Quanto custa este?'
    );
    wrapper.unmount();
  });

  it('shows the reason the server refused the photo, drops its bubble and offers no "Try again"', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: {
            code: 'foto_recusada',
            error: 'Mande uma foto parada. Foto animada não dá para ler.',
          },
        },
      })
    );
    const wrapper = montar({ fase2: true, podeGerenciar: false });
    await flushPromises();

    await anexar([foto('animada.png')]);
    await escrever('Quanto custa este?');
    await enviar();
    await vi.waitFor(() =>
      expect(corpo().find('[data-aviso="foto-recusada"]').exists()).toBe(true)
    );

    const aviso = corpo().get('[data-aviso="foto-recusada"]');
    expect(aviso.text()).toContain(
      'Mande uma foto parada. Foto animada não dá para ler.'
    );
    expect(aviso.find('button').exists()).toBe(false);
    expect(corpo().find('[data-aviso="incompleto"]').exists()).toBe(false);
    expect(corpo().findAll('[data-balao]')).toHaveLength(0);
    await flushPromises();
    expect(corpo().get('form textarea').element.value).toBe(
      'Quanto custa este?'
    );
    wrapper.unmount();
  });

  it('turns the clip on when the Fase 2 of the account arrives after the drawer opened', async () => {
    const wrapper = montar({ fase2: false, podeGerenciar: false });
    await flushPromises();
    expect(corpo().find('[data-anexar]').exists()).toBe(false);

    await wrapper.setProps({ fase2: true });
    await anexar([foto('grande.png', 5 * MB + 1)]);
    await enviar();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(corpo().find('[data-aviso="foto-recusada"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('does not read a file in the test: it asks whether the agent should learn from it', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();

    await anexar([pdf()]);
    await enviar();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(corpo().findAll('[data-balao]')).toHaveLength(0);
    const cartao = corpo().get('[data-aprender]');
    expect(cartao.text()).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.APRENDER.PERGUNTA'
    );
    expect(cartao.text()).toContain('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.SIM');
    expect(cartao.text()).toContain('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.NAO');
    wrapper.unmount();
  });

  it('"No, thanks" drops the file without keeping anything', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();
    await anexar([pdf()]);
    await enviar();

    await corpo().get('[data-nao]').trigger('click');
    await flushPromises();

    expect(corpo().find('[data-aprender]').exists()).toBe(false);
    expect(corpo().find('[data-aprendeu]').exists()).toBe(false);
    expect(store.dispatch).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('"Yes, learn" sends the file as material and links to what the agent knows', async () => {
    store.dispatch.mockResolvedValue({ id: 50 });
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();
    const cardapio = pdf();
    await anexar([cardapio]);
    await enviar();

    await corpo().get('[data-sim]').trigger('click');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/create', {
      agentId: 7,
      descriptor: { file: cardapio, kind: 'knowledge' },
    });
    expect(corpo().find('[data-aprender]').exists()).toBe(false);
    expect(corpo().get('[data-aprendeu]').text()).toContain(
      'AGENTS.JORNADA.PAGINA.TESTE.APRENDER.ENTROU'
    );
    await corpo().get('[data-ver-sabe]').trigger('click');
    expect(wrapper.emitted('verSabe')).toHaveLength(1);
    wrapper.unmount();
  });

  it('shows the server refusal of the material and keeps the question', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('Este agente já tem o máximo de 30 materiais.'), {
        status: 422,
      })
    );
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();
    await anexar([pdf()]);
    await enviar();

    await corpo().get('[data-sim]').trigger('click');
    await flushPromises();

    expect(corpo().get('[data-aprender-erro="recusa"]').text()).toContain(
      'Este agente já tem o máximo de 30 materiais.'
    );
    expect(corpo().find('[data-aprender]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('refuses a file above 25 MB before sending it', async () => {
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();
    await anexar([pdf('enorme.pdf', 25 * MB + 1)]);
    await enviar();

    await corpo().get('[data-sim]').trigger('click');
    await flushPromises();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(corpo().get('[data-aprender-erro="recusa"]').text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.GRANDE'
    );
    wrapper.unmount();
  });

  it('sends the written question and asks about the file, one file at a time', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Abrimos sim.' });
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();

    await escrever('Vocês abrem no sábado?');
    await anexar([pdf('a.pdf'), pdf('b.pdf')]);
    await enviar();
    await flushPromises();

    expect(chamadasDe('autonomiaAgents/test')[0][1]).toEqual(
      expect.objectContaining({ message: 'Vocês abrem no sábado?' })
    );
    expect(chamadasDe('autonomiaAgents/test')[0][1].images).toBeUndefined();
    expect(corpo().findAll('[data-aprender]')).toHaveLength(1);
    await corpo().get('[data-nao]').trigger('click');
    await flushPromises();
    expect(corpo().findAll('[data-aprender]')).toHaveLength(1);
    await corpo().get('[data-nao]').trigger('click');
    await flushPromises();
    expect(corpo().find('[data-aprender]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('"Clear test" also drops the files waiting for an answer', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Oi!' });
    const wrapper = montar({ fase2: true, podeGerenciar: true });
    await flushPromises();
    await escrever('Oi');
    await anexar([pdf()]);
    await enviar();
    await flushPromises();

    await corpo().get('[data-limpar]').trigger('click');
    await flushPromises();

    expect(corpo().find('[data-aprender]').exists()).toBe(false);
    wrapper.unmount();
  });
});

describe('MaterialLinha reading progress (#1427)', () => {
  const linha = (fonte, props = {}) =>
    mount(MaterialLinha, {
      props: {
        fonte: {
          id: 1,
          reference: 'catalogo-completo.pdf',
          source_type: 'pdf',
          ...fonte,
        },
        nomeAgente: 'Bia',
        ...props,
      },
    });

  it('shows "Reading page X of N" while the scanned PDF is read', () => {
    const wrapper = linha(
      {
        status: 'processing',
        metadata: { progresso: { pagina: 8, total: 30 } },
      },
      { estado: 'lendo' }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO_PAGINA'
    );
  });

  it('keeps "Reading…" without progress (a PDF with selectable text)', () => {
    const wrapper = linha(
      { status: 'processing', metadata: {} },
      { estado: 'lendo' }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO'
    );
  });

  it('shows "Reading…" with "Read again", not the page, when the reading stalled', () => {
    const wrapper = linha(
      {
        status: 'processing',
        metadata: { progresso: { pagina: 8, total: 30 } },
      },
      { estado: 'lendo', relerParado: true, podeGerenciar: true }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO'
    );
  });

  // Quem só vê não tem "Ler de novo" (a gaveta manda relerParado só a quem gerencia): quem tira a página do material
  // parado é o servidor, que só manda o progresso enquanto lê de verdade (Source#lendo_agora?).
  it('shows the page to who only views while the server says it is reading', () => {
    const wrapper = linha(
      {
        status: 'processing',
        metadata: { progresso: { pagina: 8, total: 30 } },
      },
      { estado: 'lendo', podeGerenciar: false, relerParado: false }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO_PAGINA'
    );
  });

  it('shows "Reading…" to who only views when the server drops the progress of a stalled reading', () => {
    const wrapper = linha(
      { status: 'processing', metadata: {} },
      { estado: 'lendo', podeGerenciar: false, relerParado: false }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO'
    );
    expect(wrapper.text()).not.toContain('LER_DE_NOVO');
  });

  it('drops the progress once the reading is over', () => {
    const wrapper = linha(
      {
        status: 'ready',
        metadata: { progresso: { pagina: 30, total: 30 } },
      },
      { estado: 'revisando' }
    );

    expect(wrapper.get('[data-estado-texto]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.REVISANDO'
    );
  });
});
