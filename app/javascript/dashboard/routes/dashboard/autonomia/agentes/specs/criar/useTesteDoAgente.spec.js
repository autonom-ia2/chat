import { defineComponent, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import {
  useTesteDoAgente,
  ESPERA_MAXIMA_MS,
  ESPERA_ENTRE_PARTES_MAX_MS,
} from '../../composables/useTesteDoAgente';

const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const montar = (id = 90, opcoes = undefined) => {
  let teste;
  const agente = ref({ id });
  const Casca = defineComponent({
    setup() {
      teste = useTesteDoAgente(agente, opcoes);
      return () => null;
    },
  });
  const wrapper = mount(Casca);
  return { teste, wrapper, agente };
};

const http = (status, extra = {}) =>
  Object.assign(new Error(`${status}`), { response: { status }, ...extra });
const responde = data => store.dispatch.mockResolvedValue(data);

describe('useTesteDoAgente', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    vi.stubGlobal('navigator', { onLine: true });
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    delete window.matchMedia;
  });

  it('asks the agent through the test endpoint with the previous turns as history (no images key without photos)', async () => {
    responde({ reply: 'Abrimos às 9h.', used_knowledge: [] });
    const { teste } = montar();
    await teste.enviar('Vocês abrem no sábado?');
    await teste.enviar('E no domingo?');

    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/test', {
      agentId: 90,
      message: 'E no domingo?',
      history: [
        { role: 'user', content: 'Vocês abrem no sábado?' },
        { role: 'assistant', content: 'Abrimos às 9h.' },
      ],
    });
    expect(teste.mensagens.value.map(m => m.de)).toEqual([
      'cliente',
      'agente',
      'cliente',
      'agente',
    ]);
  });

  it('plays the reply in parts, in order, typing between them (the first part does not wait)', async () => {
    vi.useFakeTimers();
    responde({
      humanized: true,
      chunks: [
        { text: 'Oi!', delay_ms: 500 },
        { text: 'Abrimos às 9h.', delay_ms: 800 },
      ],
      reply: 'Oi! Abrimos às 9h.',
      used_knowledge: [{ source: 'Horários.pdf', content: '...' }],
    });
    const { teste } = montar();
    const pronto = teste.enviar('Que horas abre?');
    await vi.advanceTimersByTimeAsync(0);
    expect(teste.mensagens.value.map(m => m.texto)).toEqual([
      'Que horas abre?',
      'Oi!',
    ]);
    expect(teste.digitando.value).toBe(true);
    expect(teste.mensagens.value[1].usou).toBeUndefined();

    await vi.advanceTimersByTimeAsync(799);
    expect(teste.mensagens.value).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(1);
    await pronto;
    expect(teste.mensagens.value[2]).toEqual({
      de: 'agente',
      texto: 'Abrimos às 9h.',
      usou: ['Horários.pdf'],
    });
    expect(teste.digitando.value).toBe(false);
    expect(teste.ultima.value).toEqual({
      pergunta: 'Que horas abre?',
      resposta: 'Oi! Abrimos às 9h.',
      passaria: false,
    });
  });

  it('never waits more than the limit between parts, whatever delay the channel asks', async () => {
    vi.useFakeTimers();
    responde({
      humanized: true,
      chunks: [
        { text: 'Oi!', delay_ms: 15000 },
        { text: 'Um momento.', delay_ms: 15000 },
        { text: 'Abrimos às 9h.', delay_ms: 15000 },
      ],
    });
    const { teste } = montar();
    const pronto = teste.enviar('Que horas abre?');
    await vi.advanceTimersByTimeAsync(0);
    expect(teste.mensagens.value).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(ESPERA_ENTRE_PARTES_MAX_MS);
    expect(teste.mensagens.value).toHaveLength(3);
    await vi.advanceTimersByTimeAsync(ESPERA_ENTRE_PARTES_MAX_MS);
    await pronto;
    expect(teste.mensagens.value).toHaveLength(4);
    expect(teste.digitando.value).toBe(false);
  });

  it('shows every part at once for who prefers reduced motion', async () => {
    vi.useFakeTimers();
    window.matchMedia = vi.fn(consulta => ({
      matches: consulta === '(prefers-reduced-motion: reduce)',
    }));
    responde({
      humanized: true,
      chunks: [
        { text: 'Oi!', delay_ms: 900 },
        { text: 'Abrimos às 9h.', delay_ms: 900 },
      ],
    });
    const { teste } = montar();
    teste.enviar('Que horas abre?');
    await vi.advanceTimersByTimeAsync(0);
    expect(teste.mensagens.value.map(m => m.texto)).toEqual([
      'Que horas abre?',
      'Oi!',
      'Abrimos às 9h.',
    ]);
  });

  it('a photo without text goes with the default text, and the photo shows in the customer bubble', async () => {
    responde({ reply: 'Bonita!' });
    const { teste } = montar(90, { textoSoFoto: 'Olha esta foto.' });
    const foto = new File(['x'], 'foto.png', { type: 'image/png' });
    await teste.enviar('', [foto]);
    await flushPromises();

    const [, dados] = store.dispatch.mock.calls[0];
    expect(dados.message).toBe('Olha esta foto.');
    expect(dados.images).toHaveLength(1);
    const cliente = teste.mensagens.value[0];
    expect(cliente.texto).toBe('Olha esta foto.');
    expect(cliente.fotos).toEqual(dados.images);
  });

  it('says which file was used only when the agent used one, and never a confidence', async () => {
    responde({ reply: 'Custa R$ 59.', confidence: 0.87, used_knowledge: [] });
    const { teste } = montar();
    await teste.enviar('Quanto custa?');

    expect(teste.mensagens.value[1]).toEqual({
      de: 'agente',
      texto: 'Custa R$ 59.',
    });
  });

  it('counts the first answer seen (the start button depends on it)', async () => {
    responde({ reply: 'Oi', used_knowledge: [] });
    const { teste } = montar();
    expect(teste.respondidas.value).toBe(0);
    await teste.enviar('Oi');
    expect(teste.respondidas.value).toBe(1);
  });

  it('marks where the agent would pass the conversation to the team', async () => {
    responde({ reply: 'Vou chamar alguém.', handoff: { should: true } });
    const { teste } = montar();
    await teste.enviar('Quero falar com uma pessoa');
    expect(teste.mensagens.value.at(-1)).toEqual({
      de: 'agente',
      texto: 'Vou chamar alguém.',
      passaria: true,
    });
    expect(teste.ultima.value.passaria).toBe(true);
    // O histórico mandado ao agente continua só com as falas.
    await teste.enviar('Ok');
    expect(store.dispatch.mock.calls[1][1].history).toEqual([
      { role: 'user', content: 'Quero falar com uma pessoa' },
      { role: 'assistant', content: 'Vou chamar alguém.' },
    ]);
  });

  it.each([
    ['incompleto', http(422)],
    ['falha', http(500)],
    ['falha', new Error('sem resposta')],
    ['demora', Object.assign(new Error('x'), { code: 'ai_request_timeout' })],
    [
      'offline',
      Object.assign(new Error('Network Error'), { code: 'ERR_NETWORK' }),
    ],
  ])(
    'shows the %s state when the test fails that way',
    async (estado, erro) => {
      store.dispatch.mockRejectedValue(erro);
      const { teste } = montar();
      await teste.enviar('Oi');
      expect(teste.aviso.value?.tipo).toBe(estado);
      expect(teste.digitando.value).toBe(false);
      expect(teste.respondidas.value).toBe(0);
    }
  );

  it('says offline when the browser has no internet, whatever the error', async () => {
    vi.stubGlobal('navigator', { onLine: false });
    store.dispatch.mockRejectedValue(http(500));
    const { teste } = montar();
    await teste.enviar('Oi');
    expect(teste.aviso.value).toEqual({ tipo: 'offline', pergunta: 'Oi' });
  });

  it('a draft without has_instruction still asks the API (the 422 decides)', async () => {
    responde({ reply: 'Oi!' });
    const { teste } = montar();
    await teste.enviar('Oi');
    expect(store.dispatch).toHaveBeenCalledTimes(1);
  });

  it('stops listening when the screen closes (a late answer is ignored)', async () => {
    let responder;
    store.dispatch.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const { teste, wrapper } = montar();
    teste.enviar('Oi');
    await flushPromises();
    wrapper.unmount();
    responder({ reply: 'Tarde demais' });
    await flushPromises();
    expect(teste.mensagens.value.map(m => m.texto)).toEqual(['Oi']);
  });

  it('gives up waiting after the limit and ignores a late answer', async () => {
    vi.useFakeTimers();
    let responder;
    store.dispatch.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const { teste } = montar();
    teste.enviar('Oi');
    await vi.advanceTimersByTimeAsync(ESPERA_MAXIMA_MS);
    expect(teste.aviso.value?.tipo).toBe('demora');

    responder({ reply: 'Tarde demais' });
    await vi.advanceTimersByTimeAsync(0);
    expect(teste.mensagens.value.map(m => m.texto)).toEqual(['Oi']);
  });

  it('retries the same question without repeating the customer bubble', async () => {
    store.dispatch.mockRejectedValueOnce(http(500));
    const { teste } = montar();
    await teste.enviar('Oi');
    responde({ reply: 'Olá!' });
    await teste.tentarDeNovo();

    expect(teste.aviso.value).toBeNull();
    expect(teste.mensagens.value.map(m => m.texto)).toEqual(['Oi', 'Olá!']);
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'autonomiaAgents/test',
      expect.objectContaining({ message: 'Oi', history: [] })
    );
  });

  it('sends photos inline as data-urls (never to the knowledge base)', async () => {
    responde({ reply: 'Bonita!' });
    const { teste } = montar();
    const foto = new File(['x'], 'foto.png', { type: 'image/png' });
    await teste.enviar('Tem esta?', [foto]);
    await flushPromises();

    const [, dados] = store.dispatch.mock.calls[0];
    expect(dados.images).toHaveLength(1);
    expect(dados.images[0].startsWith('data:image/png;base64,')).toBe(true);
    expect(store.dispatch).toHaveBeenCalledTimes(1);
  });

  it('ignores an empty question or one asked while the agent is typing', async () => {
    store.dispatch.mockReturnValue(new Promise(() => {}));
    const { teste } = montar();
    await teste.enviar('   ');
    expect(store.dispatch).not.toHaveBeenCalled();
    teste.enviar('Oi');
    teste.enviar('De novo');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledTimes(1);
  });

  it('forgets the answers seen when the agent changed (start waits for an answer of the new version)', async () => {
    responde({ reply: 'Olá!' });
    const { teste } = montar();
    await teste.enviar('Oi');
    expect(teste.respondidas.value).toBe(1);
    teste.marcarAtualizado();
    expect(teste.respondidas.value).toBe(0);
  });

  it('clears the test, and marks it updated when the agent changed', async () => {
    responde({ reply: 'Olá!' });
    const { teste } = montar();
    await teste.enviar('Oi');
    teste.marcarAtualizado();
    expect(teste.mensagens.value).toEqual([]);
    expect(teste.atualizado.value).toBe(true);

    await teste.enviar('Oi de novo');
    expect(teste.atualizado.value).toBe(false);
    teste.limpar();
    expect(teste.mensagens.value).toEqual([]);
    expect(teste.aviso.value).toBeNull();
  });
});
