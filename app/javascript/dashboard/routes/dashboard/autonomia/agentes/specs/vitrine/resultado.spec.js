import { linhasDoResultado } from '../../vitrine/resultado';

// #2858 F2 — o resultado do "Experimente" em linhas legíveis. Os `dados` seguem os formatos das fontes do servidor
// (app/services/autonomia/ferramentas_prontas/fontes). Campo sem rótulo não aparece (nunca a chave crua).
const ROTULOS = {
  cep: 'CEP',
  logradouro: 'Rua',
  bairro: 'Bairro',
  cidade: 'Cidade',
  uf: 'Estado',
  estado: 'Estado',
  razao_social: 'Razão social',
  situacao: 'Situação',
  abertura: 'Aberta em',
  atividade_principal_descricao: 'Atividade principal',
  valido: 'Número válido?',
  estados: 'Estados da região',
  cidades: 'Cidades',
  valor: 'Valor',
  modelo: 'Modelo',
  ano_modelo: 'Ano',
  precos: 'Anos na tabela',
  compra: 'Compra',
  venda: 'Venda',
  dias_uteis: 'Dias úteis',
  feriados_no_periodo: 'Feriados no período',
  busca: 'Busca',
  codigo: 'Código',
  descricao: 'Descrição',
  vigente_desde: 'Em vigor desde',
  itens: 'Resultados',
  corretores: 'Corretores',
  registro_susep: 'Registro na SUSEP',
  ramos: 'Ramos',
  seguradoras: 'Seguradoras',
  seguradora: 'Seguradora',
  produtos: 'Produtos',
};
const textos = {
  rotulo: chave => ROTULOS[chave] || '',
  maisN: ({ nomes, n }) => `${nomes} e mais ${n}`,
  sim: 'Sim',
  nao: 'Não',
  zeroKm: 'Zero quilômetro',
  idioma: 'pt-BR',
};

describe('linhasDoResultado', () => {
  it('turns the address into labeled lines, in order', () => {
    expect(
      linhasDoResultado(
        {
          cep: '01001-000',
          logradouro: 'Praça da Sé',
          bairro: 'Sé',
          cidade: 'São Paulo',
          uf: 'SP',
        },
        textos
      )
    ).toEqual([
      ['CEP', '01001-000'],
      ['Rua', 'Praça da Sé'],
      ['Bairro', 'Sé'],
      ['Cidade', 'São Paulo'],
      ['Estado', 'SP'],
    ]);
  });

  it('a field without a label never shows (no raw key)', () => {
    const linhas = linhasDoResultado(
      {
        ispb: '60701190',
        fonte_dos_dados: 'algo',
        cidade: 'Campinas',
      },
      textos
    );
    expect(linhas).toEqual([['Cidade', 'Campinas']]);
    expect(JSON.stringify(linhas)).not.toContain('ispb');
  });

  it('a list becomes the first three names and how many more', () => {
    const cidades = [
      'Acrelândia',
      'Assis Brasil',
      'Brasiléia',
      'Bujari',
      'Capixaba',
    ];
    expect(
      linhasDoResultado(
        { uf: 'AC', estado: 'Acre', total: 22, cidades },
        textos
      )
    ).toEqual([
      ['Estado', 'Acre'],
      ['Cidades', 'Acrelândia, Assis Brasil, Brasiléia e mais 19'],
    ]);
  });

  it('a short list is just joined', () => {
    expect(
      linhasDoResultado(
        { valido: true, estados: ['Espírito Santo', 'Rio de Janeiro'] },
        textos
      )
    ).toEqual([
      ['Número válido?', 'Sim'],
      ['Estados da região', 'Espírito Santo e Rio de Janeiro'],
    ]);
  });

  it('a list of named items uses the names', () => {
    expect(
      linhasDoResultado(
        {
          de: '2026-11-10',
          dias_uteis: 14,
          feriados_no_periodo: [
            { data: '2026-11-20', nome: 'Dia da Consciência Negra' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Dias úteis', '14'],
      ['Feriados no período', 'Dia da Consciência Negra'],
    ]);
  });

  it('a nested object opens one level, with the parent in the label', () => {
    expect(
      linhasDoResultado(
        {
          razao_social: 'PETROLEO BRASILEIRO S A PETROBRAS',
          situacao: 'ATIVA',
          atividade_principal: {
            codigo: '600001',
            descricao: 'Extração de petróleo e gás natural',
          },
        },
        textos
      )
    ).toEqual([
      ['Razão social', 'PETROLEO BRASILEIRO S A PETROBRAS'],
      ['Situação', 'ATIVA'],
      ['Atividade principal', 'Extração de petróleo e gás natural'],
    ]);
  });

  it('a list of unnamed items opens the first one and counts them', () => {
    expect(
      linhasDoResultado(
        {
          precos: [
            { valor: 'R$ 60.822,00', modelo: 'ONIX LT', ano_modelo: 2020 },
            { valor: 'R$ 99.000,00', modelo: 'ONIX LT', ano_modelo: 32000 },
          ],
        },
        textos
      )
    ).toEqual([
      ['Valor', 'R$ 60.822,00'],
      ['Modelo', 'ONIX LT'],
      ['Ano', '2020'],
      ['Anos na tabela', '2'],
    ]);
  });

  // #2858 F4 — a busca da NCM: o nome de cada item é a descrição; depois, o primeiro aberto (o código).
  it('a list named by another field (descricao) shows the names, then the first one', () => {
    expect(
      linhasDoResultado(
        {
          busca: 'parafuso',
          total: 12,
          mostrando: 2,
          itens: [
            {
              codigo: '73.18',
              descricao: 'Parafusos, pinos ou pernos',
              vigente_desde: '2022-04-01',
            },
            { codigo: '7318.14.00', descricao: '-- Parafusos autoperfurantes' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Busca', 'parafuso'],
      [
        'Resultados',
        'Parafusos, pinos ou pernos, -- Parafusos autoperfurantes e mais 10',
      ],
      ['Código', '73.18'],
      ['Em vigor desde', new Date(2022, 3, 1).toLocaleDateString('pt-BR')],
    ]);
  });

  it('a list of named items also opens the details of the first one', () => {
    expect(
      linhasDoResultado(
        {
          total: 1,
          corretores: [
            {
              nome: 'CORRETORA EXEMPLO LTDA',
              situacao: 'Ativo',
              registro_susep: '100000000',
              ramos: ['Pessoas', 'Danos', 'Capitalização', 'Previdência'],
            },
          ],
        },
        textos
      )
    ).toEqual([
      ['Corretores', 'CORRETORA EXEMPLO LTDA'],
      ['Situação', 'Ativo'],
      ['Registro na SUSEP', '100000000'],
      ['Ramos', 'Pessoas, Danos, Capitalização e mais 1'],
    ]);
  });

  it('a list inside the first item becomes its names, counted by that item', () => {
    const produtos = ['Cyber A', 'Cyber B', 'Cyber C', 'Cyber D'].map(nome => ({
      nome,
      coberturas: ['Danos a terceiros'],
    }));
    expect(
      linhasDoResultado(
        {
          seguradoras: [
            { seguradora: 'Seguradora Exemplo', total: 10, produtos },
            { seguradora: 'Outra Exemplo', total: 0, produtos: [] },
          ],
        },
        textos
      )
    ).toEqual([
      ['Seguradoras', 'Seguradora Exemplo e Outra Exemplo'],
      ['Produtos', 'Cyber A, Cyber B, Cyber C e mais 7'],
    ]);
  });

  it('the count of an unnamed list is the total, not just the ones sent', () => {
    expect(
      linhasDoResultado(
        { total: 37, precos: [{ valor: 'R$ 1,00' }, { valor: 'R$ 2,00' }] },
        textos
      )
    ).toEqual([
      ['Valor', 'R$ 1,00'],
      ['Anos na tabela', '37'],
    ]);
  });

  it('formats dates, numbers with the unit, and the brand-new year', () => {
    const [[, data]] = linhasDoResultado({ abertura: '1966-09-28' }, textos);
    expect(data).toBe(new Date(1966, 8, 28).toLocaleDateString('pt-BR'));
    expect(
      linhasDoResultado(
        { compra: 5.514, venda: 5.5146, unidade: 'R$', indicador: 'x' },
        textos
      )
    ).toEqual([
      ['Compra', 'R$ 5,514'],
      ['Venda', 'R$ 5,5146'],
    ]);
    expect(
      linhasDoResultado({ precos: [{ ano_modelo: 32000 }] }, textos)
    ).toEqual([['Ano', 'Zero quilômetro']]);
  });

  it('empty values and anything that is not an object give no lines', () => {
    expect(linhasDoResultado({ bairro: null, cidades: [] }, textos)).toEqual(
      []
    );
    expect(linhasDoResultado(null, textos)).toEqual([]);
    expect(linhasDoResultado('texto', textos)).toEqual([]);
  });
});
