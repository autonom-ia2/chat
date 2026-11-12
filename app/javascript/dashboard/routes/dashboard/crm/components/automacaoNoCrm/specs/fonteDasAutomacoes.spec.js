import {
  MARCA_DA_DEMO,
  criarFonteFalsa,
  marcaDaDemo,
} from '../fonteDasAutomacoes';

// #2414 F6.3/F6.5 — a fonte falsa só liga no funil que o seed da demo marcou, só na etapa marcada e só em card
// aberto; o formato é o da Automação livre (receita com gatilho e passos), sem frase pronta.
const t = chave => chave;
const marca = { etapa_id: 12 };
const funil = { metadata: { [MARCA_DA_DEMO]: marca } };
const entrou = '2026-11-12T12:00:00.000Z';
const card = {
  id: 5,
  status: 'open',
  stage_id: 12,
  entered_stage_at: entrou,
};

describe('marcaDaDemo', () => {
  it('liga só com a marca do seed (no build de desenvolvimento)', () => {
    expect(marcaDaDemo(funil)).toEqual(marca);
    expect(marcaDaDemo({ metadata: {} })).toBeNull();
    expect(marcaDaDemo({ metadata: { [MARCA_DA_DEMO]: true } })).toBeNull();
    expect(marcaDaDemo(null)).toBeNull();
  });
});

describe('criarFonteFalsa', () => {
  it('a etapa marcada tem as automações novas, com gatilho de etapa e passos', async () => {
    const itens = await criarFonteFalsa({ t, marca }).automacoesDaEtapa(12);
    expect(itens.map(item => item.receita.gatilho)).toEqual([
      { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
      { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
      { tipo: 'card.parado', etapa_id: 12, dias: 5 },
    ]);
    expect(itens.map(item => item.ativa)).toEqual([true, true, false]);
    itens.forEach(item =>
      expect(item.receita.passos.length).toBeGreaterThan(0)
    );
    expect(itens.some(item => 'faz' in item || 'quando' in item)).toBe(false);
  });

  it('outra etapa, sem marca ou ?demo=vazio: nada', async () => {
    expect(await criarFonteFalsa({ t, marca }).automacoesDaEtapa(13)).toEqual(
      []
    );
    expect(
      await criarFonteFalsa({ t, marca: null }).automacoesDaEtapa(12)
    ).toEqual([]);
    expect(
      await criarFonteFalsa({ t, marca, vazio: true }).automacoesDaEtapa(12)
    ).toEqual([]);
  });

  it('o card aberto da etapa tem o passo atual, a espera e o histórico', async () => {
    const [lembrete, deNovo] = await criarFonteFalsa({
      t,
      marca,
    }).automacoesDoCard(card);
    expect(lembrete).toMatchObject({
      id: 'motor-41',
      passoAtual: 0,
      situacao: { tipo: 'espera', ate: '2026-11-15T12:00:00.000Z' },
      comecou: entrou,
      historico: [],
    });
    expect(deNovo).toMatchObject({
      id: 'motor-42',
      passoAtual: 1,
      situacao: { tipo: 'espera', ate: '2026-11-14T12:00:00.000Z' },
      historico: [{ em: entrou, passo: 0 }],
    });
  });

  it('card ganho, perdido, arquivado ou de outra etapa não tem automação rodando', async () => {
    const fonte = criarFonteFalsa({ t, marca });
    await Promise.all(
      ['won', 'lost', 'archived'].map(async status =>
        expect(await fonte.automacoesDoCard({ ...card, status })).toEqual([])
      )
    );
    expect(await fonte.automacoesDoCard({ ...card, stage_id: 13 })).toEqual([]);
  });

  it('desligar na etapa tira a automação do card', async () => {
    const fonte = criarFonteFalsa({ t, marca });
    const [, deNovo] = await fonte.automacoesDaEtapa(12);
    expect(await fonte.ligarNaEtapa(deNovo, false)).toBe(false);
    const doCard = await fonte.automacoesDoCard(card);
    expect(doCard.map(item => item.id)).toEqual(['motor-41']);
    await fonte.ligarNaEtapa(deNovo, true);
  });
});
