import {
  acharNaReceita,
  automacoesDaEtapa,
  automacoesDoCard,
  indiceDoPrincipal,
  ligarNaEtapa,
  pararNoCard,
} from '../fonteDasAutomacoes';

// #2499 F6.3/F6.5 — a fonte lê a API do card e da etapa e entrega no formato das telas: o passo atual achado em
// qualquer galho, o passo principal que o contém, a situação (espera, condição ou agindo) e o que já fez. Ligar e
// desligar pela etapa é o da própria automação.
const { api, automacoes } = vi.hoisted(() => ({
  api: { doCard: vi.fn(), pararNoCard: vi.fn(), daEtapa: vi.fn() },
  automacoes: { ligar: vi.fn(), desligar: vi.fn() },
}));
vi.mock('dashboard/api/crmAutomacoesNoCrm', () => ({ default: api }));
vi.mock('dashboard/api/autonomia/automacoes', () => ({ default: automacoes }));

const passos = [
  { id: 'p1', tipo: 'mensagem' },
  {
    id: 'p2',
    tipo: 'se',
    entao: [{ id: 'p2a', tipo: 'esperar' }],
    senao: [{ id: 'p2b', tipo: 'avisar' }],
  },
];

describe('fonteDasAutomacoes', () => {
  beforeEach(() => {
    [...Object.values(api), ...Object.values(automacoes)].forEach(fn =>
      fn.mockReset()
    );
  });

  it('acha o passo em qualquer galho e o principal que o contém', () => {
    expect(acharNaReceita(passos, 'p2b')).toEqual({
      id: 'p2b',
      tipo: 'avisar',
    });
    expect(acharNaReceita(passos, 'x')).toBeNull();
    expect(indiceDoPrincipal(passos, 'p1')).toBe(0);
    expect(indiceDoPrincipal(passos, 'p2a')).toBe(1);
    expect(indiceDoPrincipal(passos, 'x')).toBe(-1);
  });

  it('o card aberto vem da API, com a situação e o que já fez', async () => {
    api.doCard.mockResolvedValue({
      data: {
        automacoes: [
          {
            id: 7,
            automacao_id: 41,
            nome: 'Lembrete',
            estado: 'esperando',
            passo: 'p2a',
            comecou: '2026-11-12T12:00:00Z',
            esperando_ate: '2026-11-15T12:00:00Z',
            receita: { gatilho: {}, passos },
            feitos: [
              { passo: 'p1', em: '2026-11-12T12:00:01Z' },
              { passo: 'sumiu', em: '2026-11-12T12:00:02Z' },
            ],
          },
          {
            id: 8,
            automacao_id: 42,
            nome: 'Sem prazo',
            estado: 'esperando',
            passo: 'p1',
            esperando_sem_prazo: true,
            receita: { gatilho: {}, passos },
          },
          {
            id: 9,
            automacao_id: 43,
            nome: 'Andando',
            estado: 'andando',
            passo: null,
            receita: { passos },
          },
        ],
      },
    });
    const [lembrete, semPrazo, andando] = await automacoesDoCard({
      id: 5,
      status: 'open',
    });
    expect(api.doCard).toHaveBeenCalledWith(5);
    expect(lembrete).toMatchObject({
      id: 7,
      automacaoId: 41,
      nome: 'Lembrete',
      passo: { id: 'p2a', tipo: 'esperar' },
      indice: 1,
      situacao: { tipo: 'espera', ate: '2026-11-15T12:00:00Z' },
      comecou: '2026-11-12T12:00:00Z',
    });
    // O passo que a versão não tem não vira linha.
    expect(lembrete.historico).toEqual([
      { em: '2026-11-12T12:00:01Z', passo: { id: 'p1', tipo: 'mensagem' } },
    ]);
    expect(semPrazo.situacao).toEqual({ tipo: 'condicao' });
    expect(andando).toMatchObject({
      passo: null,
      indice: -1,
      situacao: { tipo: 'agindo' },
    });
  });

  it('card fechado não pergunta ao servidor', async () => {
    expect(await automacoesDoCard({ id: 5, status: 'won' })).toEqual([]);
    expect(api.doCard).not.toHaveBeenCalled();
  });

  it('parar no card manda a automação, não a execução', async () => {
    api.pararNoCard.mockResolvedValue({ data: { paradas: 1 } });
    await pararNoCard({ id: 5 }, { id: 7, automacaoId: 41 });
    expect(api.pararNoCard).toHaveBeenCalledWith(5, 41);
  });

  it('a etapa vem da API com a versão; ligar leva a versão e desligar não', async () => {
    api.daEtapa.mockResolvedValue({
      data: {
        automacoes: [
          {
            id: 41,
            nome: 'Lembrete',
            ativa: false,
            versao: { id: 401, receita: { passos } },
          },
        ],
      },
    });
    const [item] = await automacoesDaEtapa(12);
    expect(api.daEtapa).toHaveBeenCalledWith(12);
    expect(item).toEqual({
      id: 41,
      nome: 'Lembrete',
      ativa: false,
      versaoId: 401,
      receita: { passos },
    });

    automacoes.ligar.mockResolvedValue({ data: { ativa: true } });
    expect(await ligarNaEtapa(item, true)).toBe(true);
    expect(automacoes.ligar).toHaveBeenCalledWith(41, 401);

    automacoes.desligar.mockResolvedValue({ data: { ativa: false } });
    expect(await ligarNaEtapa(item, false)).toBe(false);
    expect(automacoes.desligar).toHaveBeenCalledWith(41);
  });
});
