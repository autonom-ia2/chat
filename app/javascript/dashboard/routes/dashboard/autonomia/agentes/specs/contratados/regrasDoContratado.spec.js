import {
  GAVETA,
  ehContratado,
  gavetaDaUrl,
  gavetasPermitidas,
  podeMudarConversando,
} from '../../utils/pagina';

// #3211 (Tarefa 28) — as regras da página do agente contratado: só as gavetas que ele usa (sem Instruções, Versões,
// Conversas, Agenda nem Ferramentas, que a API recusa para ele), a gaveta própria (dados da corretora e acesso) e
// nada de mudar conversando (o Construtor recusa o contratado com 422).
const contratado = extra => ({
  id: 9,
  mode: 'guided',
  agent_type: 'sdr',
  status: 'draft',
  contratado: {
    modelo: 'seguro_viagem_universal',
    nome_agente: 'Bia',
    nome_corretora: 'Corretora Exemplo',
    sobre_corretora: '',
    acesso: null,
  },
  ...extra,
});
const TODAS_AS_OPCOES = {
  agendaNova: true,
  superAdmin: true,
  ferramentas: true,
};

describe('regras do agente contratado (#3211)', () => {
  it('knows the hired agent by the server block, never by the type', () => {
    expect(ehContratado(contratado())).toBe(true);
    expect(ehContratado({ agent_type: 'sdr', contratado: null })).toBe(false);
    expect(ehContratado({ agent_type: 'sdr' })).toBe(false);
    expect(ehContratado({ agent_type: 'insurance_quote' })).toBe(false);
    expect(ehContratado(null)).toBe(false);
  });

  it('gives whoever manages exactly its own drawers, Saber read-only and no Tools', () => {
    expect(gavetasPermitidas(contratado(), true)).toEqual([
      GAVETA.CONTRATADO,
      GAVETA.ONDE,
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.FOTO,
      GAVETA.VOLTAR,
    ]);
    expect(gavetasPermitidas(contratado(), true, TODAS_AS_OPCOES)).toEqual([
      GAVETA.CONTRATADO,
      GAVETA.ONDE,
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.FOTO,
      GAVETA.VOLTAR,
    ]);
  });

  it('gives whoever only views testing and reading', () => {
    expect(gavetasPermitidas(contratado(), false)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
    ]);
    expect(gavetasPermitidas(contratado(), false, TODAS_AS_OPCOES)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
    ]);
  });

  it('never changes the hired agent by chatting', () => {
    expect(podeMudarConversando(contratado())).toBe(false);
    expect(podeMudarConversando(contratado({ mode: 'manual' }))).toBe(false);
  });

  it('opens its drawer from ?gaveta=contratado', () => {
    expect(gavetaDaUrl(undefined, 'contratado')).toBe(GAVETA.CONTRATADO);
    expect(gavetaDaUrl('channels', 'contratado')).toBe(GAVETA.ONDE);
  });

  // Os outros agentes seguem com as listas de antes desta tarefa.
  it('keeps the quote agent (Lia) and the ordinary agents with the same drawers as before', () => {
    const cotacao = { agent_type: 'insurance_quote' };
    const guiado = { mode: 'guided', agent_type: 'sdr', contratado: null };
    const interno = { mode: 'guided', actuation: 'internal' };

    expect(gavetasPermitidas(cotacao, true)).toEqual([
      GAVETA.ONDE,
      GAVETA.VOLTAR,
      GAVETA.FOTO,
    ]);
    expect(gavetasPermitidas(cotacao, true, { superAdmin: true })).toEqual([
      GAVETA.ONDE,
      GAVETA.VOLTAR,
      GAVETA.FOTO,
      GAVETA.FERRAMENTAS,
    ]);
    expect(gavetasPermitidas(cotacao, false)).toEqual([]);

    expect(gavetasPermitidas(guiado, false)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.VERSOES,
    ]);
    expect(gavetasPermitidas(guiado, true, TODAS_AS_OPCOES)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.VERSOES,
      GAVETA.CONVERSAS,
      GAVETA.FOTO,
      GAVETA.INSTRUCOES,
      GAVETA.ONDE,
      GAVETA.VOLTAR,
      GAVETA.AGENDA,
      GAVETA.FERRAMENTAS,
    ]);
    expect(gavetasPermitidas(interno, true)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.VERSOES,
      GAVETA.CONVERSAS,
      GAVETA.FOTO,
      GAVETA.INSTRUCOES,
    ]);
    expect(podeMudarConversando(guiado)).toBe(true);
    expect(podeMudarConversando(cotacao)).toBe(false);
    [cotacao, guiado, interno].forEach(agente =>
      expect(gavetasPermitidas(agente, true)).not.toContain(GAVETA.CONTRATADO)
    );
  });
});
