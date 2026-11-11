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
  primeiro_da_lista: 'Primeiro da lista',
  estabelecimentos: 'Locais de saúde',
  endereco: 'Endereço',
  telefone: 'Telefone',
  nome: 'Nome',
  nome_completo: 'Nome completo',
  valor_estimado: 'Valor estimado (R$)',
  data: 'Data',
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
      ['Data', new Date(2026, 10, 20).toLocaleDateString('pt-BR')],
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

  // #2858 F4 — a busca da NCM: o nome de cada item é a descrição (sem os traços da tabela); o primeiro aberto traz o
  // nome dele na primeira linha, para não parecer que o código vale para todos.
  it('a list named by another field (descricao) shows the names, then the first one with its name', () => {
    expect(
      linhasDoResultado(
        {
          busca: 'parafuso',
          total: 12,
          mostrando: 2,
          itens: [
            {
              codigo: '7318.14.00',
              descricao: '-- Parafusos autoperfurantes',
              vigente_desde: '2022-04-01',
            },
            { codigo: '73.18', descricao: 'Parafusos, pinos ou pernos' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Busca', 'parafuso'],
      [
        'Resultados',
        'Parafusos autoperfurantes, Parafusos, pinos ou pernos e mais 10',
      ],
      ['Primeiro da lista', 'Parafusos autoperfurantes'],
      ['Código', '7318.14.00'],
      ['Em vigor desde', new Date(2022, 3, 1).toLocaleDateString('pt-BR')],
    ]);
  });

  it('opens the first of many only with two labeled fields besides the name', () => {
    expect(
      linhasDoResultado(
        {
          total: 20,
          estabelecimentos: [
            {
              nome: 'HOSPITAL EXEMPLO',
              endereco: 'RUA A, 1',
              telefone: '19 0000-0000',
              cnes: '1',
            },
            { nome: 'CLÍNICA EXEMPLO', endereco: 'RUA B, 2' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Locais de saúde', 'HOSPITAL EXEMPLO, CLÍNICA EXEMPLO e mais 18'],
      ['Primeiro da lista', 'HOSPITAL EXEMPLO'],
      ['Endereço', 'RUA A, 1'],
      ['Telefone', '19 0000-0000'],
    ]);
    // Um campo só (o código da marca, a data do feriado): só os nomes.
    expect(
      linhasDoResultado(
        {
          feriados_no_periodo: [
            { data: '2026-11-15', nome: 'Proclamação da República' },
            { data: '2026-11-20', nome: 'Dia da consciência negra' },
          ],
        },
        textos
      )
    ).toEqual([
      [
        'Feriados no período',
        'Proclamação da República e Dia da consciência negra',
      ],
    ]);
  });

  it('a list of one opens its details without repeating the name', () => {
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
          ],
        },
        textos
      )
    ).toEqual([
      ['Seguradoras', 'Seguradora Exemplo'],
      ['Produtos', 'Cyber A, Cyber B, Cyber C e mais 7'],
    ]);
  });

  it('the dash is taken only from names and descriptions, never from another text', () => {
    expect(
      linhasDoResultado(
        { observacao: '-0,5 ponto no mês', descricao: '- Tachas e pregos' },
        {
          ...textos,
          rotulo: chave =>
            ({ observacao: 'Observação', descricao: 'Descrição' })[chave] || '',
        }
      )
    ).toEqual([
      ['Observação', '-0,5 ponto no mês'],
      ['Descrição', 'Tachas e pregos'],
    ]);
  });

  // "1 item" é a lista inteira de um só: com o total maior (a fonte mandou 1 de 5), é o primeiro de muitos.
  it('one item sent out of a bigger total follows the rule of many', () => {
    expect(
      linhasDoResultado(
        {
          total: 5,
          corretores: [{ nome: 'CORRETORA EXEMPLO LTDA', situacao: 'Ativo' }],
        },
        textos
      )
    ).toEqual([['Corretores', 'CORRETORA EXEMPLO LTDA e mais 4']]);
  });

  it('money has the thousands separator; the full name equal to the name does not repeat', () => {
    expect(
      linhasDoResultado({ compras: [{ valor_estimado: 1789431.34 }] }, textos)
    ).toEqual([['Valor estimado (R$)', '1.789.431,34']]);
    expect(
      linhasDoResultado({ compras: [{ valor_estimado: 52224 }] }, textos)
    ).toEqual([['Valor estimado (R$)', '52.224,00']]);
    expect(
      linhasDoResultado({ venda: 12345.5, unidade: 'R$' }, textos)
    ).toEqual([['Venda', 'R$ 12.345,50']]);
    // A PTAX tem 4 casas: dinheiro mostra no mínimo 2 e no máximo 4.
    expect(
      linhasDoResultado({ compra: 5.5834, venda: 5.5, unidade: 'R$' }, textos)
    ).toEqual([
      ['Compra', 'R$ 5,5834'],
      ['Venda', 'R$ 5,50'],
    ]);
    expect(
      linhasDoResultado(
        {
          codigo: '341',
          nome: 'ITAÚ UNIBANCO S.A.',
          nome_completo: 'ITAÚ UNIBANCO S.A.',
        },
        textos
      )
    ).toEqual([
      ['Código', '341'],
      ['Nome', 'ITAÚ UNIBANCO S.A.'],
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
