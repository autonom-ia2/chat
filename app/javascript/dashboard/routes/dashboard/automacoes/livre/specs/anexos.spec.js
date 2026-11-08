import { linhasDoEnsaio } from '../ensaio';

// #2414 G20 — o passo de IA que lê os anexos: no ensaio, quantos desta
// conversa a IA leria (junto do que o passo faria), ou por que não seria
// chamada.
const t = (chave, valores, n) =>
  `${chave}${valores && Object.keys(valores).length ? `(${Object.values(valores).join(',')})` : ''}${n === undefined ? '' : `#${n}`}`;

const fraseDe = id => `frase ${id}`;
const linha = no => linhasDoEnsaio([no], fraseDe, t)[0];

describe('linhasDoEnsaio com os anexos', () => {
  it('junta quantos anexos a IA leria ao que o passo faria', () => {
    expect(
      linha({
        id: 'i1',
        tipo: 'resumir',
        faria: 'ia_resumir',
        dados: { destino: 'nota', anexos: 2 },
      }).destaque
    ).toBe(
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_RESUMIR_NOTA AUTOMACAO_LIVRE.IA.ANEXOS.LERIA(2)#2'
    );
  });

  it('no decidir, que não tem destaque próprio, mostra só os anexos', () => {
    expect(
      linha({
        id: 'd1',
        tipo: 'decidir',
        faria: 'decidir',
        dados: { anexos: 0 },
      }).destaque
    ).toBe('AUTOMACAO_LIVRE.IA.ANEXOS.LERIA(0)#0');
  });

  it('o anexo que não pode ir à IA vira o aviso', () => {
    expect(
      linha({
        id: 'i1',
        tipo: 'resumir',
        faria: 'ia_resumir',
        dados: { destino: 'nota', anexos_motivo: 'anexo_grande_demais' },
      }).aviso
    ).toBe('AUTOMACAO_LIVRE.IA.ANEXOS.ANEXO_GRANDE_DEMAIS');
  });

  it('sem pedir os anexos, a linha fica como era', () => {
    expect(
      linha({
        id: 'i1',
        tipo: 'resumir',
        faria: 'ia_resumir',
        dados: { destino: 'nota' },
      })
    ).toEqual({
      nivel: 0,
      tipo: 'resumir',
      texto: 'frase i1',
      destaque: 'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_RESUMIR_NOTA',
    });
  });
});
