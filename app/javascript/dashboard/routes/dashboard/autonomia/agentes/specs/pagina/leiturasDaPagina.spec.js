import { ref } from 'vue';
import {
  ESTADO_PAGINA,
  useAgenteDaPagina,
} from '../../composables/useAgenteDaPagina';
import { useCanaisDoAgente } from '../../composables/useCanaisDoAgente';
import {
  AVISO_TESTE,
  ESPERA_MAXIMA_MS,
  useTesteDoAgente,
} from '../../composables/useTesteDoAgente';

const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  getters: { 'autonomiaAgents/getRecord': () => ({}) },
}));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const agentesApi = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: agentesApi }));
const jornadaApi = vi.hoisted(() => ({ canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornadaApi }));
const canaisApi = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));

const erroHttp = status =>
  Object.assign(new Error('x'), { response: { status } });

describe('useAgenteDaPagina', () => {
  beforeEach(() => store.dispatch.mockReset());

  it('loads the agent and keeps it in the store', async () => {
    agentesApi.show.mockResolvedValue({ data: { id: 7, name: 'Bia' } });
    const { estado, carregar } = useAgenteDaPagina(ref('7'));
    await carregar();
    expect(agentesApi.show).toHaveBeenCalledWith(7);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/upsert', {
      id: 7,
      name: 'Bia',
    });
    expect(estado.value).toBe(ESTADO_PAGINA.PRONTO);
  });

  it('tells "no longer exists" (404) apart from a failure', async () => {
    agentesApi.show.mockRejectedValueOnce(erroHttp(404));
    const pagina = useAgenteDaPagina(ref(7));
    await pagina.carregar();
    expect(pagina.estado.value).toBe(ESTADO_PAGINA.NAO_EXISTE);

    agentesApi.show.mockRejectedValueOnce(erroHttp(500));
    await pagina.carregar();
    expect(pagina.estado.value).toBe(ESTADO_PAGINA.ERRO);
  });
});

describe('useCanaisDoAgente', () => {
  it('reads every inbox from L2', async () => {
    jornadaApi.canaisOcupados.mockResolvedValue({
      data: {
        payload: [
          {
            inbox_id: 1,
            name: 'WhatsApp',
            occupied_by: { kind: 'agent', agent_id: 7 },
          },
          { inbox_id: 2, name: 'Site', occupied_by: null },
        ],
      },
    });
    const canais = useCanaisDoAgente(ref('7'));
    await canais.carregar();
    expect(canais.estado.value).toBe('pronto');
    expect(canais.semLeitura.value).toBe(false);
    expect(canais.atuais.value.map(canal => canal.inbox_id)).toEqual([1]);
    expect(canaisApi.get).not.toHaveBeenCalled();
  });

  it('falls back to the agent channels when L2 fails, without the busy inboxes', async () => {
    jornadaApi.canaisOcupados.mockRejectedValue(new Error('404'));
    canaisApi.get.mockResolvedValue({
      data: {
        payload: [{ inbox_id: 1, inbox_name: 'WhatsApp', channel_type: 'x' }],
        eligible_inboxes: [{ id: 3, name: 'Instagram', channel_type: 'y' }],
      },
    });
    const canais = useCanaisDoAgente(ref(7));
    await canais.carregar();
    expect(canais.semLeitura.value).toBe(true);
    expect(canais.canais.value).toEqual([
      {
        inbox_id: 1,
        name: 'WhatsApp',
        channel_type: 'x',
        occupied_by: { kind: 'agent', agent_id: 7 },
      },
      { inbox_id: 3, name: 'Instagram', channel_type: 'y', occupied_by: null },
    ]);
    expect(canais.atuais.value).toHaveLength(1);
  });

  it('reports an error when both reads fail', async () => {
    jornadaApi.canaisOcupados.mockRejectedValue(new Error('x'));
    canaisApi.get.mockRejectedValue(new Error('y'));
    const canais = useCanaisDoAgente(ref(7));
    await canais.carregar();
    expect(canais.estado.value).toBe('erro');
    expect(canais.canais.value).toEqual([]);
  });
});

describe('useTesteDoAgente', () => {
  const agente = ref({ id: 7, has_instruction: true });

  beforeEach(() => {
    vi.useRealTimers();
    store.dispatch.mockReset();
    agente.value = { id: 7, has_instruction: true };
  });

  it('asks as a customer and plays the reply in parts, with the file used', async () => {
    store.dispatch.mockResolvedValue({
      humanized: true,
      chunks: [{ text: 'Abrimos sim.' }, { text: 'Das 9h às 13h.' }],
      used_knowledge: [
        { source: 'horarios.pdf' },
        { source: 'horarios.pdf' },
        { source: 'imagem da mensagem' },
      ],
      handoff: { should: false },
      confidence: 0.91,
    });
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Vocês abrem no sábado?');

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/test', {
      agentId: 7,
      message: 'Vocês abrem no sábado?',
      history: [],
    });
    expect(teste.mensagens.value).toEqual([
      { de: 'cliente', texto: 'Vocês abrem no sábado?' },
      { de: 'agente', texto: 'Abrimos sim.', usou: [] },
      { de: 'agente', texto: 'Das 9h às 13h.', usou: ['horarios.pdf'] },
    ]);
    expect(JSON.stringify(teste.mensagens.value)).not.toContain('0.91');
    expect(teste.ultima.value).toEqual({
      pergunta: 'Vocês abrem no sábado?',
      resposta: 'Abrimos sim. Das 9h às 13h.',
      passaria: false,
    });
  });

  it('sends the previous turns as history and flags a handoff', async () => {
    store.dispatch
      .mockResolvedValueOnce({ reply: 'Oi!' })
      .mockResolvedValueOnce({
        reply: 'Já chamo alguém.',
        handoff: { should: true },
      });
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Oi');
    await teste.enviar('Quero falar com uma pessoa');

    expect(store.dispatch.mock.calls[1][1].history).toEqual([
      { role: 'user', content: 'Oi' },
      { role: 'assistant', content: 'Oi!' },
    ]);
    expect(teste.ultima.value.passaria).toBe(true);
  });

  it('shows a failure and retries the same question', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Quanto custa?');
    expect(teste.aviso.value).toEqual({
      tipo: AVISO_TESTE.FALHA,
      pergunta: 'Quanto custa?',
    });

    store.dispatch.mockResolvedValueOnce({ reply: 'R$ 10' });
    await teste.tentarDeNovo();
    expect(teste.aviso.value).toBeNull();
    expect(teste.mensagens.value.map(m => m.texto)).toEqual([
      'Quanto custa?',
      'R$ 10',
    ]);
  });

  it('says it is taking too long and ignores the late reply', async () => {
    vi.useFakeTimers();
    let responder;
    store.dispatch.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const teste = useTesteDoAgente(agente);
    const envio = teste.enviar('Oi');
    vi.advanceTimersByTime(ESPERA_MAXIMA_MS);
    expect(teste.aviso.value.tipo).toBe(AVISO_TESTE.DEMORA);
    expect(teste.digitando.value).toBe(false);

    responder({ reply: 'atrasada' });
    await envio;
    expect(teste.mensagens.value.map(m => m.texto)).toEqual(['Oi']);
  });

  it('treats the polling timeout as slow, not as a failure', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('t'), { code: 'ai_request_timeout' })
    );
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Oi');
    expect(teste.aviso.value.tipo).toBe(AVISO_TESTE.DEMORA);
  });

  it('does not call the API for an agent that does not know enough yet', async () => {
    agente.value = { id: 7, has_instruction: false };
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Oi');
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(teste.aviso.value.tipo).toBe(AVISO_TESTE.INCOMPLETO);
  });

  it('clears, marks as updated and shows a past exchange', async () => {
    store.dispatch.mockResolvedValue({ reply: 'Oi!' });
    const teste = useTesteDoAgente(agente);
    await teste.enviar('Oi');
    teste.marcarAtualizado();
    expect(teste.mensagens.value).toEqual([]);
    expect(teste.atualizado.value).toBe(true);

    teste.mostrar({ pergunta: 'P?', resposta: 'R.' });
    expect(teste.mensagens.value).toEqual([
      { de: 'cliente', texto: 'P?' },
      { de: 'agente', texto: 'R.' },
    ]);
    expect(teste.atualizado.value).toBe(false);
  });
});
