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
  precos: 'Preços na tabela',
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
  indicador: 'Indicador',
  expectativas: 'Anos com previsão',
  mediana: 'Previsão do mercado (mediana)',
  data_do_boletim: 'Boletim de',
  telefones: 'Telefones',
  tipo: 'Tipo',
  ocorrencias: 'Ocorrências',
  ocorrencias_12_meses: 'Ocorrências em 12 meses',
  processos: 'Processos',
  assunto: 'Assunto',
  obras: 'Obras',
  veiculos: 'Veículos',
  variacoes: 'Variações',
  combustivel: 'Combustível',
  numero: 'Número',
  placa: 'Placa',
  cno: 'CNO',
  mm: 'Chuva no dia (mm)',
  observacao: 'Observação',
  ano: 'Ano',
  dias: 'Dias',
};
const dataPt = (ano, mes, dia) =>
  new Date(ano, mes - 1, dia).toLocaleDateString('pt-BR');
const textos = {
  rotulo: chave => ROTULOS[chave] || '',
  maisN: ({ nomes, n }) => `${nomes} e mais ${n}`,
  sim: 'Sim',
  nao: 'Não',
  zeroKm: 'Zero quilômetro',
  nenhumValor: '—',
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

  // #2858 F7 — lista sem nome com mais de um item: o primeiro sob "Primeiro da lista", identificado pelo primeiro campo
  // identificador que houver (o ano do preço do carro); a lista mostra os identificadores, não só quantos são.
  it('a list without a name field is identified by its first identifier field', () => {
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
      ['Ano', '2020 e Zero quilômetro'],
      ['Primeiro da lista', '2020'],
      ['Valor', 'R$ 60.822,00'],
      ['Modelo', 'ONIX LT'],
    ]);
  });

  it('the second phone does not vanish, and the first one is named', () => {
    expect(
      linhasDoResultado(
        {
          telefones: [
            { numero: '(11) 1111-1111', tipo: 'celular', endereco: 'RUA A, 1' },
            { numero: '(11) 2222-2222', tipo: 'fixo', endereco: 'RUA B, 2' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Número', '(11) 1111-1111 e (11) 2222-2222'],
      ['Primeiro da lista', '(11) 1111-1111'],
      ['Tipo', 'celular'],
      ['Endereço', 'RUA A, 1'],
    ]);
  });

  // `tipo` é categoria, não identifica (C27): as ocorrências por tipo só são contadas, e o "em 12 meses" do primeiro não
  // fica solto ao lado do total.
  it('a category (tipo) does not identify: the list is counted', () => {
    expect(
      linhasDoResultado(
        {
          ocorrencias_12_meses: 12,
          ocorrencias: [
            { tipo: 'Furto', ocorrencias_12_meses: 9 },
            { tipo: 'Roubo', ocorrencias_12_meses: 3 },
          ],
        },
        textos
      )
    ).toEqual([
      ['Ocorrências em 12 meses', '12'],
      ['Ocorrências', '2'],
    ]);
    const linhas = linhasDoResultado(
      {
        estabelecimentos_sem_nome: [
          { tipo: 'Hospital geral', data: '2026-11-10', endereco: 'RUA A' },
          { tipo: 'Hospital geral', data: '2026-11-10', endereco: 'RUA B' },
        ],
      },
      {
        ...textos,
        rotulo: chave =>
          chave === 'estabelecimentos_sem_nome'
            ? 'Locais'
            : ROTULOS[chave] || '',
      }
    );
    expect(linhas).toEqual([['Locais', '2']]);
    expect(JSON.stringify(linhas)).not.toContain(
      'Hospital geral e Hospital geral'
    );
    expect(JSON.stringify(linhas)).not.toContain(
      `${dataPt(2026, 11, 10)} e ${dataPt(2026, 11, 10)}`
    );
  });

  it('identifiers: works (cno) and vehicles (placa); dates as dates', () => {
    expect(
      linhasDoResultado(
        {
          obras: [
            { cno: '90.000.00001/71', endereco: 'RUA A, 1' },
            { cno: '90.000.00002/72', endereco: 'RUA B, 2' },
          ],
          veiculos: [
            { placa: 'ABC1D23', modelo: 'ONIX' },
            { placa: 'XYZ9W87' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Endereço', '90.000.00001/71: RUA A, 1 · 90.000.00002/72: RUA B, 2'],
      ['Modelo', 'ABC1D23: ONIX · XYZ9W87: —'],
    ]);
  });

  // Regra A (#2858, regra final): identificador sem rótulo não identifica (nunca a chave crua nem o rótulo da lista).
  it('an identifier without a label does not identify: the list is counted', () => {
    expect(
      linhasDoResultado(
        {
          telefones: [
            { numero: '1111', tipo: 'celular', endereco: 'RUA A' },
            { numero: '2222', tipo: 'fixo', endereco: 'RUA B' },
          ],
        },
        {
          ...textos,
          rotulo: chave => (chave === 'numero' ? '' : ROTULOS[chave] || ''),
        }
      )
    ).toEqual([['Telefones', '2']]);
  });

  it('a list inside the opened item also uses the label of its identifier', () => {
    expect(
      linhasDoResultado(
        {
          corretores: [
            {
              nome: 'Corretora A',
              telefones: [
                { numero: '1111', tipo: 'celular' },
                { numero: '2222', tipo: 'fixo' },
              ],
            },
          ],
        },
        textos
      )
    ).toEqual([
      ['Corretores', 'Corretora A'],
      ['Número', '1111 e 2222'],
    ]);
  });

  // #2858 (revisão do #2891) — identificador só serve se não se repete: a FIPE com dois combustíveis do mesmo ano
  // mostrava "2020 e 2020".
  it('a repeated field is not an identifier: the next one is tried, and without any the list is counted', () => {
    const preco = (valor, combustivel) => ({
      valor,
      modelo: 'ONIX',
      ano_modelo: 2020,
      combustivel,
    });
    expect(
      linhasDoResultado(
        {
          precos: [
            preco('R$ 56.043,00', 'Gasolina'),
            preco('R$ 58.000,00', 'Flex'),
          ],
        },
        textos
      )
    ).toEqual([
      ['Combustível', 'Gasolina e Flex'],
      ['Primeiro da lista', 'Gasolina'],
      ['Valor', 'R$ 56.043,00'],
      ['Modelo', 'ONIX'],
      ['Ano', '2020'],
    ]);
    expect(
      linhasDoResultado(
        {
          telefones: [
            { tipo: 'celular', data: '2026-11-10' },
            { tipo: 'celular', data: '2026-11-10' },
          ],
        },
        textos
      )
    ).toEqual([['Telefones', '2']]);
    // Mesmo ano e mesmo combustível: nenhum identificador distinto, só a contagem com o rótulo da lista.
    expect(
      linhasDoResultado(
        {
          precos: [
            preco('R$ 56.043,00', 'Flex'),
            preco('R$ 58.000,00', 'Flex'),
          ],
        },
        textos
      )
    ).toEqual([['Preços na tabela', '2']]);
  });

  it('several days of rain, the first without a value: the pairs with a dash', () => {
    expect(
      linhasDoResultado(
        {
          dias: [
            { data: '2026-11-08', mm: null },
            { data: '2026-11-09', mm: 1.2 },
            { data: '2026-11-10', mm: 1.8 },
          ],
        },
        {
          ...textos,
          rotulo: chave =>
            ({ dias: 'Dias', data: 'Data', mm: 'Chuva no dia (mm)' })[chave] ||
            '',
        }
      )
    ).toEqual([
      [
        'Chuva no dia (mm)',
        `${dataPt(2026, 11, 8)}: — · ${dataPt(2026, 11, 9)}: 1,2 · ${dataPt(2026, 11, 10)}: 1,8`,
      ],
    ]);
    expect(
      linhasDoResultado(
        { dias: [{ data: '2026-11-09', mm: 1.2 }, { data: '2026-11-10' }] },
        textos
      )
    ).toEqual([
      [
        'Chuva no dia (mm)',
        `${dataPt(2026, 11, 9)}: 1,2 · ${dataPt(2026, 11, 10)}: —`,
      ],
    ]);
  });

  // A chuva de hoje: o dia de hoje ainda sem mm e com observação. Campos diferentes entre os itens não viram par.
  it('items with different fields do not become pairs', () => {
    expect(
      linhasDoResultado(
        {
          dias: [
            { data: '2026-11-10', mm: 1.8 },
            { data: '2026-11-11', mm: null, observacao: 'Ainda sem medição' },
          ],
        },
        textos
      )
    ).toEqual([['Data', `${dataPt(2026, 11, 10)} e ${dataPt(2026, 11, 11)}`]]);
    expect(
      linhasDoResultado(
        {
          dias: [
            { data: '2026-11-10', mm: 1 },
            { data: '2026-11-11', focos: 3 },
          ],
        },
        {
          ...textos,
          rotulo: chave => (chave === 'focos' ? 'Focos' : ROTULOS[chave] || ''),
        }
      )
    ).toEqual([['Data', `${dataPt(2026, 11, 10)} e ${dataPt(2026, 11, 11)}`]]);
  });

  it('one labeled field besides the identifier: the pairs in one line', () => {
    const queimadas = {
      ...textos,
      rotulo: chave =>
        ({ dias_com_focos: 'Dias com focos', data: 'Data', focos: 'Focos' })[
          chave
        ] || '',
    };
    expect(
      linhasDoResultado(
        {
          dias_com_focos: [
            { data: '2026-11-10', focos: 5 },
            { data: '2026-11-11', focos: 3 },
          ],
        },
        queimadas
      )
    ).toEqual([
      ['Focos', `${dataPt(2026, 11, 10)}: 5 · ${dataPt(2026, 11, 11)}: 3`],
    ]);
    const dias = [6, 7, 8, 9, 10].map(dia => ({
      data: `2026-11-${String(dia).padStart(2, '0')}`,
      focos: dia,
    }));
    expect(
      linhasDoResultado({ total: 9, dias_com_focos: dias }, queimadas)
    ).toEqual([
      [
        'Focos',
        `${dataPt(2026, 11, 6)}: 6 · ${dataPt(2026, 11, 7)}: 7 · ${dataPt(2026, 11, 8)}: 8 · e mais 6`,
      ],
    ]);
  });

  it('a date with time is shown in the language, with the hour, without time zone conversion', () => {
    const rotulo = chave => (chave === 'data' ? 'Data' : '');
    const em = (data, idioma = 'pt-BR') =>
      linhasDoResultado({ data }, { ...textos, rotulo, idioma });
    const pt = `${dataPt(2026, 11, 11)} 03:10`;
    expect(em('2026-11-11 03:10')).toEqual([['Data', pt]]);
    expect(em('2026-11-11T03:10')).toEqual([['Data', pt]]);
    expect(em('2026-11-11 03:10:45')).toEqual([['Data', pt]]);
    expect(em('2026-11-11T03:10:00.123456')).toEqual([['Data', pt]]);
    const local = new Date(2026, 10, 11, 3, 10);
    const hora = local.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
    });
    expect(em('2026-11-11 03:10', 'en-US')).toEqual([
      ['Data', `${local.toLocaleDateString('en-US')} ${hora}`],
    ]);
  });

  // Revisão do 99654ff88f: lista sem rótulo não aparece, nem pelo identificador (coberturas fica de fora de propósito).
  it('a list without a label shows nothing, not even by its identifier', () => {
    const coberturas = [
      { ano: 2020, valor: 'R$ 1,00', modelo: 'A' },
      { ano: 2021, valor: 'R$ 2,00', modelo: 'B' },
    ];
    const rotulo = chave =>
      chave === 'coberturas' ? '' : ROTULOS[chave] || '';
    expect(linhasDoResultado({ coberturas }, { ...textos, rotulo })).toEqual(
      []
    );
    expect(
      linhasDoResultado(
        { coberturas: coberturas.map(({ ano, valor }) => ({ ano, valor })) },
        { ...textos, rotulo }
      )
    ).toEqual([]);
    expect(
      linhasDoResultado(
        { corretores: [{ nome: 'Corretora A', coberturas }] },
        { ...textos, rotulo }
      )
    ).toEqual([['Corretores', 'Corretora A']]);
    expect(
      linhasDoResultado({ plano: { coberturas } }, { ...textos, rotulo })
    ).toEqual([]);
  });

  it('an impossible date comes as it was sent, with or without the hour', () => {
    const rotulo = chave => (chave === 'data' ? 'Data' : '');
    const em = data => linhasDoResultado({ data }, { ...textos, rotulo });
    [
      '2026-02-31',
      '2026-00-10',
      '2026-02-31 10:00',
      '2026-00-10 10:00',
    ].forEach(texto => expect(em(texto)).toEqual([['Data', texto]]));
  });

  it('a date with time out of the exact format comes as it was sent', () => {
    const rotulo = chave => (chave === 'data' ? 'Data' : '');
    const em = data => linhasDoResultado({ data }, { ...textos, rotulo });
    [
      '2026-11-11 25:99',
      '2026-11-11 23:60',
      '2026-11-11 03:10 reunião do conselho',
      '2026-11-11T03:10:00Z',
      '2026-11-11T03:10:00-03:00',
      '2026-11-11T03:10:00.',
      '2026-11-11 03:1',
    ].forEach(texto => expect(em(texto)).toEqual([['Data', texto]]));
  });

  it('every number has the thousands separator, except the identification ones', () => {
    const rotulo = chave => chave;
    expect(
      linhasDoResultado(
        {
          potencia: 54977.7,
          total_mm: 1234.5,
          populacao: 1500000,
          ano: 2026,
          ano_modelo: 2020,
          cep: 38400100,
          codigo: 7318,
          codigo_ibge: 3170206,
          registro_susep: 202012345,
          matricula: 123456,
          numero: 10001,
          cnpj: 12345678000199,
          cpf: 12345678909,
          ispb: 60701190,
          cnes: 2146355,
          ddd: 3400,
          rntrc: 12345678,
          unidades: { potencia: 'kW' },
        },
        { ...textos, rotulo }
      )
    ).toEqual([
      ['potencia', '54.977,7 kW'],
      ['total_mm', '1.234,5'],
      ['populacao', '1.500.000'],
      ['ano', '2026'],
      ['ano_modelo', '2020'],
      ['cep', '38400100'],
      ['codigo', '7318'],
      ['codigo_ibge', '3170206'],
      ['registro_susep', '202012345'],
      ['matricula', '123456'],
      ['numero', '10001'],
      ['cnpj', '12345678000199'],
      ['cpf', '12345678909'],
      ['ispb', '60701190'],
      ['cnes', '2146355'],
      ['ddd', '3400'],
      ['rntrc', '12345678'],
    ]);
    expect(
      linhasDoResultado(
        { ano: 2026, valor: 1234.5, unidade: '%' },
        { ...textos, rotulo: chave => (chave === 'unidade' ? '' : chave) }
      )
    ).toEqual([
      ['ano', '2026'],
      ['valor', '1.234,5 %'],
    ]);
  });

  it('a field named like an Object property is not taken as a unit', () => {
    expect(
      linhasDoResultado(
        { constructor: 5, itens: [{ toString: 2 }] },
        { ...textos, rotulo: chave => chave }
      )
    ).toEqual([
      ['constructor', '5'],
      ['toString', '2'],
    ]);
  });

  it('without a name or an identifier, a list of many is only counted', () => {
    expect(
      linhasDoResultado(
        {
          total: 37,
          processos: [
            { assunto: 'Cobrança', valor: 'R$ 1,00' },
            { assunto: 'Despejo', valor: 'R$ 2,00' },
          ],
        },
        textos
      )
    ).toEqual([['Processos', '37']]);
  });

  // #2858 F7 (C02) — a unidade de um campo dentro do item vem de `unidades` (campo -> unidade), no nível de cima.
  it('the unit of a field inside the items comes from unidades', () => {
    expect(
      linhasDoResultado(
        {
          indicador: 'Focus: IPCA',
          unidades: { mediana: '%' },
          expectativas: [
            { ano: 2026, mediana: 5.2195, data_do_boletim: '2026-11-06' },
            { ano: 2027, mediana: 4.9, data_do_boletim: '2026-11-06' },
          ],
        },
        textos
      )
    ).toEqual([
      ['Indicador', 'Focus: IPCA'],
      ['Ano', '2026 e 2027'],
      ['Primeiro da lista', '2026'],
      ['Previsão do mercado (mediana)', '5,2195 %'],
      ['Boletim de', new Date(2026, 10, 6).toLocaleDateString('pt-BR')],
    ]);
    expect(
      linhasDoResultado(
        {
          unidades: { mediana: 'R$' },
          expectativas: [{ ano: 2026, mediana: 5.4 }],
        },
        textos
      )
    ).toEqual([
      ['Ano', '2026'],
      ['Previsão do mercado (mediana)', 'R$ 5,40'],
    ]);
  });

  // #2858 (C14) — lista de valores simples: número no formato do idioma, e o sinal fica.
  it('a list of plain numbers keeps the sign and the language format', () => {
    expect(linhasDoResultado({ variacoes: [-0.5, 1, 2.25] }, textos)).toEqual([
      ['Variações', '-0,5, 1 e 2,25'],
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

  it('the identifiers of a list count by the total, not just the ones sent', () => {
    expect(
      linhasDoResultado(
        {
          total: 37,
          precos: [
            { valor: 'R$ 1,00', ano_modelo: 2020 },
            { valor: 'R$ 2,00', ano_modelo: 2021 },
          ],
        },
        textos
      )
    ).toEqual([['Valor', '2020: R$ 1,00 · 2021: R$ 2,00 · e mais 35']]);
  });

  it('formats dates, numbers with the unit, and the brand-new year', () => {
    const [[, data]] = linhasDoResultado({ abertura: '1966-09-28' }, textos);
    expect(data).toBe(new Date(1966, 8, 28).toLocaleDateString('pt-BR'));
    expect(
      linhasDoResultado(
        { compra: 5.514, venda: 5.5146, unidade: 'R$', serie: 'x' },
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
