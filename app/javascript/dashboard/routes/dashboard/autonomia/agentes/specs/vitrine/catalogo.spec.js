import { withFullI18n } from 'test-i18n';
import {
  FERRAMENTAS,
  GRUPOS,
  chaveDoTexto,
  emDestaque,
  ferramentaPorId,
  liberadas,
} from '../../vitrine/catalogo';

// #2858 F2 — o catálogo da tela: só as fontes que o servidor tem (F0 + F1 + F4), com as chaves dele, os textos no i18n e o
// destaque pelo ramo da conta.
const i18n = withFullI18n('pt_BR');
const { te } = i18n.global;

const CHAVES_DO_SERVIDOR = [
  'cep',
  'cnpj',
  'fipe',
  'cpf',
  'feriados',
  'banco_central',
  'cidades',
  'ddd',
  'localizacao',
  'bancos',
  'hospitais',
  'procedimentos',
  'doencas',
  'ncm',
  'compras_governo',
  'estacoes',
  'chuva',
  'produtos_seguradoras',
  'corretor_susep',
];

describe('catálogo da vitrine', () => {
  it('has exactly the sources the server has', () => {
    expect(FERRAMENTAS.map(item => item.id).sort()).toEqual(
      [...CHAVES_DO_SERVIDOR].sort()
    );
  });

  it('every card has its texts in pt_BR and en, and every group exists', () => {
    ['pt_BR', 'en'].forEach(locale => {
      FERRAMENTAS.forEach(item => {
        const base = `AGENTS.VITRINE.FERRAMENTAS.${chaveDoTexto(item.id)}`;
        ['NOME', 'FAZ', 'CONSEGUE', 'CLIENTE', 'AGENTE', 'USE_QUANDO'].forEach(
          campo => expect(te(`${base}.${campo}`, locale)).toBe(true)
        );
        expect(te(`${base}.ROTULO`, locale)).toBe(true);
        if (!item.semCampo) expect(te(`${base}.EXEMPLO`, locale)).toBe(true);
        expect(GRUPOS.some(grupo => grupo.id === item.grupo)).toBe(true);
      });
    });
  });

  // #2858, regra "QI 70": o exemplo do Experimente é o que um leigo escreveria, não o código técnico.
  it('examples are what a lay person types, not technical codes', () => {
    const { t } = i18n.global;
    expect(t('AGENTS.VITRINE.FERRAMENTAS.PROCEDIMENTOS.EXEMPLO')).toBe(
      'hemograma'
    );
    expect(t('AGENTS.VITRINE.FERRAMENTAS.DOENCAS.EXEMPLO')).toBe('asma');
    expect(t('AGENTS.VITRINE.FERRAMENTAS.BANCOS.EXEMPLO')).toBe('Itaú');
    expect(t('AGENTS.VITRINE.FERRAMENTAS.BANCOS.USE_QUANDO')).toContain(
      'o nome ou o código de um banco'
    );
  });

  it('shows only what the server released, in the showcase order', () => {
    expect(liberadas(['bancos', 'cep', 'desconhecida']).map(i => i.id)).toEqual(
      ['cep', 'bancos']
    );
  });

  it('highlights by the account field, or the most chosen without one', () => {
    const todas = liberadas(CHAVES_DO_SERVIDOR);
    expect(emDestaque(todas, ['seguros']).map(i => i.id)).toEqual([
      'cpf',
      'cep',
      'fipe',
      'produtos_seguradoras',
      'corretor_susep',
    ]);
    expect(emDestaque(todas, []).map(i => i.id)).toEqual([
      'cnpj',
      'cep',
      'banco_central',
      'feriados',
    ]);
    expect(emDestaque(liberadas(['cep']), ['seguros']).map(i => i.id)).toEqual([
      'cep',
    ]);
  });

  it('the business days example is always a future date as day/month/year', () => {
    const exemplo = ferramentaPorId('feriados').exemplo(new Date(2026, 10, 10));
    expect(exemplo).toBe('30/11/2026');
  });

  // Em inglês, "01/12/2026" se lê 12 de janeiro: o mês vai por extenso.
  it('in English the business days example spells the month out', () => {
    const feriados = ferramentaPorId('feriados');
    expect(feriados.exemplo(new Date(2026, 10, 10), 'en')).toBe(
      'November 30, 2026'
    );
    expect(feriados.exemplo(new Date(2026, 10, 10), 'pt_BR')).toBe(
      '30/11/2026'
    );
  });
});
