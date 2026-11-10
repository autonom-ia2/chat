import { withFullI18n } from 'test-i18n';
import {
  FERRAMENTAS,
  GRUPOS,
  chaveDoTexto,
  emDestaque,
  ferramentaPorId,
  liberadas,
} from '../../vitrine/catalogo';

// #2858 F2 — o catálogo da tela: só as fontes que o servidor tem (F0 + F1), com as chaves dele, os textos no i18n e o
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
});
