import { gatilhoDaUrl } from '../gatilhoDaUrl';

// #2414 F6.5 — o editor abre com o gatilho da etapa vindo da URL, só se a
// pessoa pode escolhê-lo; qualquer outra coisa abre o editor como sempre.
const OFERECIDOS = [
  { tipo: 'conversa.criada' },
  { tipo: 'card.entrou_na_etapa' },
  { tipo: 'card.saiu_da_etapa' },
];

describe('gatilhoDaUrl', () => {
  it('monta o gatilho de etapa com a etapa_id', () => {
    expect(
      gatilhoDaUrl({ gatilho: 'card.entrou_na_etapa', etapa: '12' }, OFERECIDOS)
    ).toEqual({ tipo: 'card.entrou_na_etapa', etapa_id: 12 });
    expect(
      gatilhoDaUrl({ gatilho: 'card.saiu_da_etapa', etapa: '3' }, OFERECIDOS)
    ).toEqual({ tipo: 'card.saiu_da_etapa', etapa_id: 3 });
  });

  it('ignora gatilho que não é de etapa, etapa inválida ou não oferecida', () => {
    expect(
      gatilhoDaUrl({ gatilho: 'conversa.criada', etapa: '12' }, OFERECIDOS)
    ).toBeNull();
    expect(
      gatilhoDaUrl({ gatilho: 'card.entrou_na_etapa', etapa: 'x' }, OFERECIDOS)
    ).toBeNull();
    expect(
      gatilhoDaUrl({ gatilho: 'card.entrou_na_etapa', etapa: '0' }, OFERECIDOS)
    ).toBeNull();
    expect(
      gatilhoDaUrl({ gatilho: 'card.entrou_na_etapa', etapa: '12' }, [
        { tipo: 'conversa.criada' },
      ])
    ).toBeNull();
    expect(gatilhoDaUrl({}, OFERECIDOS)).toBeNull();
  });
});
