import { withFullI18n } from 'test-i18n';
import {
  FERRAMENTAS,
  GRUPOS,
  chaveDoTexto,
  emDestaque,
  ferramentaPorId,
  larguraDoCartao,
  liberadas,
  oferecida,
  premiumPorUltimo,
} from '../../vitrine/catalogo';

// #2858 F2 — o catálogo da tela: só as fontes que o servidor tem (F0 + F1 + F4 + F5 + F7), com as chaves dele, os textos no i18n e o
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
  // F5 (bases baixadas)
  'planos_de_saude',
  'aeronaves',
  'geracao_solar',
  'transportadoras',
  'queimadas',
  // F7 (Premium)
  'certidoes_empresa',
  'raio_x_empresa',
  'conferir_pessoa',
  'historico_placa',
  'risco_endereco',
  'imovel_rural',
  'contato_empresa',
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
        // Todo card tem "Experimente", o Premium também (F7, decisão A do Rodrigo, 11/11).
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

  // Decisão do Rodrigo (11/11/2026): Produtos das seguradoras fica só para os agentes de garantia e de transporte.
  it('never offers an internal-use source, even if the server sends it, but still knows it for the agent drawer', () => {
    expect(liberadas(CHAVES_DO_SERVIDOR).map(i => i.id)).not.toContain(
      'produtos_seguradoras'
    );
    expect(oferecida('produtos_seguradoras')).toBe(false);
    expect(oferecida('corretor_susep')).toBe(true);
    expect(oferecida('desconhecida')).toBe(false);
    expect(ferramentaPorId('produtos_seguradoras').icone).toBe(
      'i-lucide-file-search'
    );
  });

  it('highlights by the account field, or the most chosen without one', () => {
    const todas = liberadas(CHAVES_DO_SERVIDOR);
    expect(emDestaque(todas, ['seguros']).map(i => i.id)).toEqual([
      'cpf',
      'cep',
      'fipe',
      'corretor_susep',
      'planos_de_saude',
      'transportadoras',
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

  it('the 7 Premium cards sit in the group of their subject, after the free ones, with the price texts in both languages, and never highlighted', () => {
    const premium = FERRAMENTAS.filter(item => item.premium);
    expect(premium.map(item => item.id)).toEqual([
      'certidoes_empresa',
      'raio_x_empresa',
      'conferir_pessoa',
      'historico_placa',
      'risco_endereco',
      'imovel_rural',
      'contato_empresa',
    ]);
    expect(
      Object.fromEntries(premium.map(item => [item.id, item.grupo]))
    ).toEqual({
      certidoes_empresa: 'PESSOAS',
      raio_x_empresa: 'PESSOAS',
      conferir_pessoa: 'PESSOAS',
      historico_placa: 'VEICULOS',
      risco_endereco: 'LUGAR',
      imovel_rural: 'LUGAR',
      contato_empresa: 'CLIENTES',
    });
    expect(GRUPOS.map(grupo => grupo.id)).not.toContain('PREMIUM');
    const pessoas = premiumPorUltimo(
      liberadas(CHAVES_DO_SERVIDOR).filter(item => item.grupo === 'PESSOAS')
    );
    expect(pessoas.map(item => item.id)).toEqual([
      'cnpj',
      'cpf',
      'certidoes_empresa',
      'raio_x_empresa',
      'conferir_pessoa',
    ]);
    // A Premium que vem antes de uma grátis vai para o fim; a ordem entre as de cada tipo fica.
    const misturadas = [
      'certidoes_empresa',
      'cnpj',
      'conferir_pessoa',
      'cpf',
    ].map(ferramentaPorId);
    expect(premiumPorUltimo(misturadas).map(item => item.id)).toEqual([
      'cnpj',
      'cpf',
      'certidoes_empresa',
      'conferir_pessoa',
    ]);
    expect(misturadas.map(item => item.id)).toEqual([
      'certidoes_empresa',
      'cnpj',
      'conferir_pessoa',
      'cpf',
    ]);
    ['pt_BR', 'en'].forEach(locale => {
      [
        'SELO',
        'LEGENDA',
        'DEPOIS',
        'AGORA',
        'FAIXA',
        'RESTAM',
        'RESTA_UMA',
        'ACABARAM',
        'TITULO',
        'CONTADOR.RESTAM',
        'CONTADOR.RESTA_UMA',
        'VOLTAM',
        'PRECO_DEPOIS',
        'PRECO_AGORA',
        'POR_CONSULTA',
        'REGRAS.SEM_RESULTADO',
        'REGRAS.NUMERO_ERRADO',
        'REGRAS.MESMO_DIA',
        'REGRAS.FAIXA',
        'REGRAS.FATURA',
      ].forEach(campo =>
        expect(te(`AGENTS.VITRINE.PREMIUM.${campo}`, locale)).toBe(true)
      );
      expect(te('AGENTS.VITRINE.GRUPOS.PREMIUM.NOME', locale)).toBe(false);
    });
    const todas = liberadas(CHAVES_DO_SERVIDOR);
    expect(emDestaque(todas, ['seguros']).some(item => item.premium)).toBe(
      false
    );
    expect(emDestaque(todas, []).some(item => item.premium)).toBe(false);
    expect(ferramentaPorId('historico_placa').premium).toBe(true);
  });
});

// Nenhum cartão sozinho na última linha da grade de 3 no computador: com sobra de 1, os 4 últimos ficam 2 a 2.
describe('larguraDoCartao', () => {
  const larguras = total =>
    Array.from({ length: total }, (_, indice) =>
      larguraDoCartao(indice, total)
    );
  const UM_TERCO = 'lg:col-span-2';
  const METADE = 'lg:col-span-3';

  it('a group with one card keeps the normal width', () => {
    expect(larguras(1)).toEqual([UM_TERCO]);
  });

  it('two or five cards keep the normal width (no card left alone)', () => {
    expect(larguras(2)).toEqual([UM_TERCO, UM_TERCO]);
    expect(larguras(5)).toEqual(Array(5).fill(UM_TERCO));
  });

  it('four cards become two rows of two', () => {
    expect(larguras(4)).toEqual(Array(4).fill(METADE));
  });

  it('seven cards: one row of three, then two rows of two', () => {
    expect(larguras(7)).toEqual([
      ...Array(3).fill(UM_TERCO),
      ...Array(4).fill(METADE),
    ]);
  });
});
