import { linhasDoResultado } from '../../vitrine/resultado';
import { FERRAMENTAS } from '../../vitrine/catalogo';
import en from 'dashboard/i18n/locale/en/agents.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #2858 F4 — cobertura do resultado do "Experimente" com o `dados` REAL de cada fonte grátis no ar (F1 a F4): uma
// chamada real por consulta, passada pelo adaptador do servidor, gravada em ./dados-reais (de onde veio cada uma:
// ./dados-reais/README.md). Os rótulos são os do i18n de verdade, em en e em pt_BR. Falha se uma fonte voltar sem
// linhas, ou sem o essencial que o dono precisa ver.
const reais = import.meta.glob('./dados-reais/*.json', { eager: true });
const porFonte = Object.fromEntries(
  Object.entries(reais).map(([caminho, modulo]) => [
    caminho.split('/').pop().replace('.json', ''),
    modulo.default,
  ])
);

const textosEm = (mensagens, idioma, maisN) => {
  const campos = mensagens.AGENTS.VITRINE.CAMPOS;
  return {
    rotulo: chave => campos[String(chave).toUpperCase()] || '',
    maisN: ({ nomes, n }) => `${nomes} ${maisN} ${n}`,
    sim: 'S',
    nao: 'N',
    zeroKm: '0km',
    idioma,
  };
};
const PT = textosEm(ptBR, 'pt-BR', 'e mais');
const EN = textosEm(en, 'en', 'and');

const linhas = (fonte, consulta, textos = PT) =>
  linhasDoResultado(porFonte[fonte][consulta].dados, textos);
// O valor da linha com esse rótulo (pt_BR), ou undefined.
const valor = (fonte, consulta, rotulo) =>
  (linhas(fonte, consulta).find(([nome]) => nome === rotulo) || [])[1];

const CONSULTAS = Object.entries(porFonte).flatMap(([fonte, consultas]) =>
  Object.keys(consultas).map(consulta => [fonte, consulta])
);

describe('linhasDoResultado com o dado real de cada fonte', () => {
  it('há dado real de toda fonte grátis do catálogo da vitrine', () => {
    const semDadoReal = FERRAMENTAS.map(item => item.id).filter(
      id => !porFonte[id]
    );
    expect(semDadoReal).toEqual([]);
  });

  it.each(CONSULTAS)(
    '%s / %s: mostra linhas em pt_BR e em en',
    (fonte, consulta) => {
      expect(linhas(fonte, consulta, PT).length).toBeGreaterThan(0);
      expect(linhas(fonte, consulta, EN).length).toBeGreaterThan(0);
    }
  );

  it('F1–F3: endereço, empresa, CPF, carro, feriados, Banco Central, cidades, DDD, localização e banco', () => {
    expect(valor('cep', 'endereco', 'Rua')).toBe('Praça da Sé');
    expect(valor('cnpj', 'empresa', 'Razão social')).toContain('PETROBRAS');
    expect(valor('cpf', 'conferir', 'Número válido?')).toBe('S');
    expect(valor('fipe', 'marcas', 'Marcas')).toContain('Acura');
    expect(valor('fipe', 'modelos', 'Modelos')).toContain('ONIX');
    expect(valor('fipe', 'preco', 'Valor')).toContain('R$');
    expect(valor('feriados', 'feriados', 'Feriados')).toContain(
      'Confraternização'
    );
    expect(valor('feriados', 'dias_uteis', 'Dias úteis')).toBeDefined();
    expect(valor('banco_central', 'selic', 'Valor')).toContain('% ao ano');
    expect(valor('banco_central', 'ipca', 'Variação no mês')).toBeDefined();
    expect(
      valor('banco_central', 'ipca', 'Acumulado em 12 meses')
    ).toBeDefined();
    expect(valor('banco_central', 'dolar', 'Venda')).toContain('R$');
    expect(
      valor('banco_central', 'focus', 'Previsão do mercado (mediana)')
    ).toBeDefined();
    expect(valor('cidades', 'estados', 'Estados')).toContain('Acre');
    expect(valor('cidades', 'cidades', 'Cidades')).toContain('Acrelândia');
    expect(valor('ddd', 'ddd', 'Cidades')).toContain('ARAGUARI');
    expect(valor('localizacao', 'cidade', 'Cidade')).toBe('Uberlândia');
    expect(valor('bancos', 'banco', 'Nome')).toContain('ITAÚ');
  });

  it('F4: saúde (hospitais, procedimentos, doenças)', () => {
    expect(valor('hospitais', 'estabelecimentos', 'Locais de saúde')).toContain(
      'HOSPITAL'
    );
    expect(valor('hospitais', 'estabelecimentos', 'Endereço')).toBeDefined();
    expect(valor('procedimentos', 'codigo', 'Nome')).toContain('Consulta');
    expect(valor('procedimentos', 'busca', 'Resultados')).toContain(
      'Hemograma'
    );
    expect(valor('doencas', 'codigo', 'Nome')).toBe('Asma');
    expect(valor('doencas', 'busca', 'Resultados')).toContain('Asma');
  });

  it('F4: NCM com código e descrição, a busca já na ordem de relevância', () => {
    expect(valor('ncm', 'codigo', 'Código')).toBe('7318.15.00');
    expect(valor('ncm', 'codigo', 'Descrição')).toContain('parafusos');
    expect(
      valor('ncm', 'buscar', 'Resultados').startsWith('Parafusos, pinos')
    ).toBe(true);
    expect(valor('ncm', 'buscar', 'Código')).toBe('73.18');
  });

  it('F4: compras, estações e chuva com os valores', () => {
    const [primeira] = porFonte.compras_governo.compras.dados.compras;
    expect(valor('compras_governo', 'compras', 'Compras')).toContain(
      primeira.objeto
    );
    expect(valor('compras_governo', 'compras', 'Órgão')).toBe(primeira.orgao);
    // `unidade` da compra é a unidade do órgão, não a de medida: o valor sai sem ela.
    expect(valor('compras_governo', 'compras', 'Valor estimado (R$)')).toBe(
      String(primeira.valor_estimado)
    );
    expect(valor('estacoes', 'estacoes', 'Estações')).toContain('UBERLANDIA');
    expect(valor('estacoes', 'estacoes', 'Distância (km)')).toBe('2');
    expect(valor('estacoes', 'estacoes', 'Situação')).toBe('Operante');
    expect(valor('chuva', 'chuva', 'Chuva no período (mm)')).toBe('1,8');
    expect(valor('chuva', 'chuva', 'Lugar')).toBe('Uberlândia (MG)');
  });

  it('F4: seguradora com os produtos pelo nome, e corretor com nome e situação', () => {
    expect(valor('produtos_seguradoras', 'seguradoras', 'Seguradoras')).toBe(
      'ALLIANZ SEGUROS'
    );
    expect(valor('produtos_seguradoras', 'seguradoras', 'Ramos')).toBeDefined();
    expect(valor('produtos_seguradoras', 'produtos', 'Seguradoras')).toBe(
      'ALLIANZ SEGUROS'
    );
    expect(valor('produtos_seguradoras', 'produtos', 'Produtos')).toBe(
      'Responsabilidade Civil de Riscos Cibernéticos'
    );
    expect(valor('produtos_seguradoras', 'produtos', 'Ramo')).toBe(
      'Riscos cibernéticos'
    );
    expect(valor('corretor_susep', 'por_nome', 'Corretores')).toContain(
      'CORRETORA EXEMPLO 1 LTDA'
    );
    expect(valor('corretor_susep', 'por_nome', 'Situação')).toBe('Suspenso');
  });
});
