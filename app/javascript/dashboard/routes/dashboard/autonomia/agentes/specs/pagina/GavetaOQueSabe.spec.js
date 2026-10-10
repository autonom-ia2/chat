import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import GavetaOQueSabe from '../../components/pagina/GavetaOQueSabe.vue';
import { MAX_ARQUIVO } from '../../utils/pagina';

// T09 · O que sabe: arquivos e sites em palavras (sem nota nem %), mandar arquivo (até 25 MB) ou site,
// ler de novo, tirar com confirmação, erro padrão e as perguntas de clientes (FAQ que já existe).
const store = vi.hoisted(() => ({ dispatch: vi.fn(), state: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state?.[nome] ?? false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const faq = vi.hoisted(() => ({ approve: vi.fn(), ignore: vi.fn() }));
vi.mock('dashboard/api/autonomia/faqSuggestions', () => ({ default: faq }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};

const fonte = (id, extra = {}) => ({
  id,
  source_type: 'pdf',
  reference: `arquivo-${id}.pdf`,
  status: 'ready',
  review: { status: 'accepted', quality_score: 87, confidence: 0.9 },
  ...extra,
});

const preparar = (fontes = []) => {
  store.state = reactive({
    'autonomiaSources/getKnowledgeSources': fontes,
    'autonomiaSources/getUIFlags': { fetchingList: false },
  });
};

const montar = props =>
  mount(GavetaOQueSabe, {
    attachTo: document.body,
    props: {
      agente: { id: 7, name: 'Bia' },
      nome: 'Bia',
      podeGerenciar: true,
      fontes: store.state['autonomiaSources/getKnowledgeSources'],
      ...props,
    },
  });

const escolherArquivo = arquivo => {
  const seletor = no('[data-seletor]');
  Object.defineProperty(seletor, 'files', {
    value: [arquivo],
    configurable: true,
  });
  seletor.dispatchEvent(new Event('change'));
};

describe('GavetaOQueSabe', () => {
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
    store.dispatch.mockResolvedValue({});
    alerta.mockReset();
    preparar();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('shows each file in words, never a score', async () => {
    preparar([
      fonte(1),
      fonte(2, { status: 'processing', review: null }),
      fonte(3, { status: 'failed' }),
      fonte(4, {
        source_type: 'link',
        reference: 'loja.com',
        review: { status: 'needs_resend' },
      }),
    ]);
    const wrapper = montar();
    await nextTick();

    expect(todos('[data-fonte]').map(f => f.dataset.estado)).toEqual([
      'pronto',
      'lendo',
      'falha',
      'falha',
    ]);
    const texto = document.body.textContent;
    expect(texto).toContain('SABE.FALHA_ARQUIVO');
    expect(texto).toContain('SABE.FALHA_SITE');
    expect(texto).not.toContain('%');
    expect(texto).not.toContain('87');
    expect(texto).not.toContain('0.9');
    wrapper.unmount();
  });

  it('says it knows only the conversation when there are no files', async () => {
    const wrapper = montar();
    await nextTick();
    expect(no('[data-vazio]').textContent).toContain('SABE.VAZIO');
    wrapper.unmount();
  });

  it('sends a file as knowledge and refuses one above 25 MB', async () => {
    const wrapper = montar();
    await clicar('[data-mandar]');
    expect(no('[data-adicionar]')).not.toBeNull();

    escolherArquivo({ name: 'grande.pdf', size: MAX_ARQUIVO + 1 });
    await flushPromises();
    expect(no('[data-erro-arquivo]').textContent).toContain('SABE.GRANDE');
    expect(store.dispatch).not.toHaveBeenCalled();

    const arquivo = { name: 'precos.pdf', size: 10 };
    escolherArquivo(arquivo);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/create', {
      agentId: 7,
      descriptor: { file: arquivo, kind: 'knowledge' },
    });
    expect(no('[data-adicionar]')).toBeNull();
    wrapper.unmount();
  });

  it('checks the website address before sending it', async () => {
    const wrapper = montar();
    await clicar('[data-mandar]');
    const campo = no('[data-site]');
    campo.value = 'minha loja';
    campo.dispatchEvent(new Event('input'));
    await clicar('[data-mandar-site]');
    expect(no('[data-erro-site]').textContent).toContain('SABE.SITE_ERRO');
    expect(campo.getAttribute('aria-invalid')).toBe('true');
    expect(store.dispatch).not.toHaveBeenCalled();

    campo.value = 'www.sualoja.com.br';
    campo.dispatchEvent(new Event('input'));
    await clicar('[data-mandar-site]');
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/create', {
      agentId: 7,
      descriptor: { url: 'https://www.sualoja.com.br/', kind: 'knowledge' },
    });
    wrapper.unmount();
  });

  it('shows the standard error and retries the same save', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const wrapper = montar();
    await clicar('[data-mandar]');
    escolherArquivo({ name: 'a.pdf', size: 10 });
    await flushPromises();
    expect(no('[data-erro-salvar]').textContent).toContain(
      'SABE.ERRO_GARANTIA'
    );

    await clicar('[data-erro-salvar] button');
    expect(store.dispatch).toHaveBeenCalledTimes(2);
    expect(no('[data-erro-salvar]')).toBeNull();
    wrapper.unmount();
  });

  it('replaces a file it could not read: sends the new one, then removes the old', async () => {
    preparar([fonte(3, { status: 'failed' })]);
    const wrapper = montar();
    await clicar('[data-mandar-outro]');
    const arquivo = { name: 'novo.pdf', size: 10 };
    escolherArquivo(arquivo);
    await flushPromises();
    expect(store.dispatch.mock.calls.map(chamada => chamada[0])).toEqual([
      'autonomiaSources/create',
      'autonomiaSources/remove',
    ]);
    expect(store.dispatch.mock.calls[1][1]).toEqual({
      agentId: 7,
      sourceId: 3,
    });
    wrapper.unmount();
  });

  it('retries only the removal when the new file went in but the old one stayed', async () => {
    preparar([fonte(3, { status: 'failed' })]);
    store.dispatch.mockImplementation(async acao => {
      if (acao === 'autonomiaSources/remove') throw new Error('500');
      return {};
    });
    const wrapper = montar();
    await clicar('[data-mandar-outro]');
    escolherArquivo({ name: 'novo.pdf', size: 10 });
    await flushPromises();
    expect(no('[data-erro-salvar]')).not.toBeNull();

    store.dispatch.mockReset();
    store.dispatch.mockResolvedValue({});
    await clicar('[data-erro-salvar] button');
    expect(store.dispatch.mock.calls.map(chamada => chamada[0])).toEqual([
      'autonomiaSources/remove',
    ]);
    expect(no('[data-erro-salvar]')).toBeNull();
    wrapper.unmount();
  });

  it('keeps the list on screen while it is read again, and shows loading only the first time', async () => {
    const lista = [fonte(1), fonte(2)];
    const wrapper = montar({ fontes: lista });
    expect(todos('[data-fonte]')).toHaveLength(2);
    await wrapper.setProps({ fontes: [], carregandoFontes: true });
    expect(todos('[data-fonte]')).toHaveLength(0);
    expect(no('[data-vazio]')).toBeNull();
    wrapper.unmount();
  });

  it('reads a website again and removes a file after confirming', async () => {
    preparar([
      fonte(4, { source_type: 'link', reference: 'loja.com' }),
      fonte(5),
    ]);
    const wrapper = montar();
    await nextTick();
    const menus = todos('[data-fonte] [aria-haspopup="menu"]');

    menus[0].click();
    await nextTick();
    expect(todos('[role="menuitem"]').map(i => i.textContent.trim())).toEqual([
      'AGENTS.JORNADA.PAGINA.SABE.LER_DE_NOVO',
      'AGENTS.JORNADA.PAGINA.SABE.TIRAR',
    ]);
    todos('[role="menuitem"]')[0].click();
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/resync', {
      agentId: 7,
      sourceId: 4,
    });

    menus[1].click();
    await nextTick();
    expect(todos('[role="menuitem"]')).toHaveLength(1);
    todos('[role="menuitem"]')[0].click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaSources/remove', {
      agentId: 7,
      sourceId: 5,
    });
    wrapper.unmount();
  });

  it('is read-only for view-only seats', async () => {
    preparar([fonte(3, { status: 'failed' })]);
    const wrapper = montar({ podeGerenciar: false, perguntas: [{ id: 1 }] });
    await nextTick();
    expect(no('[data-mandar]')).toBeNull();
    expect(no('[data-mandar-outro]')).toBeNull();
    expect(no('[data-fonte] [aria-haspopup="menu"]')).toBeNull();
    expect(no('[data-perguntas]')).toBeNull();
    wrapper.unmount();
  });

  it('shows the read error with a retry', async () => {
    const wrapper = montar({ erroLer: true });
    await clicar('[data-erro-ler] button');
    expect(wrapper.emitted('reler')).toHaveLength(1);
    wrapper.unmount();
  });

  describe('perguntas dos clientes', () => {
    const PERGUNTAS = [
      { id: 11, question: 'Tem estacionamento?', answer: 'Sim, gratuito.' },
      { id: 12, question: 'Aceita Pix?', answer: 'Aceitamos.' },
    ];

    it('teaches one as it is', async () => {
      faq.approve.mockResolvedValue({});
      const wrapper = montar({ perguntas: PERGUNTAS });
      await nextTick();
      expect(todos('[data-pergunta]')).toHaveLength(2);
      await clicar('[data-ensinar]');
      expect(faq.approve).toHaveBeenCalledWith(7, 11);
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.SABE.ENSINOU');
      expect(wrapper.emitted('perguntaResolvida')).toEqual([[11]]);
      wrapper.unmount();
    });

    it('changes and teaches, or skips for now', async () => {
      faq.approve.mockResolvedValue({});
      faq.ignore.mockResolvedValue({});
      const wrapper = montar({ perguntas: PERGUNTAS });
      await clicar('[data-mudar]');
      const [pergunta] = todos('[data-pergunta] input');
      pergunta.value = 'Tem estacionamento grátis?';
      pergunta.dispatchEvent(new Event('input'));
      await nextTick();
      no('[data-pergunta] form').dispatchEvent(new Event('submit'));
      await flushPromises();
      expect(faq.approve).toHaveBeenCalledWith(7, 11, {
        question: 'Tem estacionamento grátis?',
        answer: 'Sim, gratuito.',
      });

      todos('[data-agora-nao]')[1].click();
      await flushPromises();
      expect(faq.ignore).toHaveBeenCalledWith(7, 12);
      wrapper.unmount();
    });
  });
});
