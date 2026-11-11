import { linhasDoResultado } from '../../vitrine/resultado';
import { FERRAMENTAS } from '../../vitrine/catalogo';
import en from 'dashboard/i18n/locale/en/agents.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #2858 F4 — cobertura do resultado do "Experimente" com o `dados` REAL de cada fonte grátis no ar (F1 a F5): uma
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
    nenhumValor: mensagens.AGENTS.VITRINE.RESULTADO.NENHUM_VALOR,
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

// Chave com "_" na frente é anotação do arquivo (a "_origem" da fixture feita à mão), não consulta.
const CONSULTAS = Object.entries(porFonte).flatMap(([fonte, consultas]) =>
  Object.keys(consultas)
    .filter(consulta => !consulta.startsWith('_'))
    .map(consulta => [fonte, consulta])
);

describe('linhasDoResultado com o dado real de cada fonte', () => {
  it('há dado real de toda fonte grátis do catálogo da vitrine', () => {
    const semDadoReal = FERRAMENTAS.map(item => item.id).filter(
      id => !porFonte[id]
    );
    expect(
      semDadoReal,
      'Fonte nova sem dado real: grave specs/vitrine/dados-reais/<id>.json pelo script (ver README.md), ' +
        'anonimize pessoa física e ponha uma asserção do essencial'
    ).toEqual([]);
  });

  it('todo arquivo de dado real tem ao menos uma consulta (chave sem "_")', () => {
    const semConsulta = Object.entries(porFonte)
      .filter(
        ([, consultas]) =>
          !Object.keys(consultas).some(chave => !chave.startsWith('_'))
      )
      .map(([fonte]) => fonte);
    expect(
      semConsulta,
      'Arquivo de dado real sem consulta: grave ao menos uma pelo script (ver README.md)'
    ).toEqual([]);
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
    // CNPJ anonimizado pelo script (a razão social do MEI traz o nome da pessoa).
    expect(valor('cnpj', 'empresa', 'CNPJ')).toBe('11.222.333/0001-81');
    expect(valor('cnpj', 'empresa', 'Razão social')).toBe(
      'EMPRESA EXEMPLO LTDA'
    );
    expect(valor('cnpj', 'empresa', 'Situação')).toBe('ATIVA');
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
    // A unidade da mediana vem em `unidades` (C02): sem ela, "5,2195" sem o "%".
    // Varredura P13: os dois anos com a previsão de cada um, sem abrir só o primeiro.
    expect(
      valor('banco_central', 'focus', 'Previsão do mercado (mediana)')
    ).toBe('2026: 5,2195 % · 2027: 4,9005 %');
    expect(
      valor('banco_central', 'focus', 'Primeiro da lista')
    ).toBeUndefined();
    // Regra A: a linha dos identificadores leva o rótulo do identificador (Ano), não o da lista.
    expect(valor('banco_central', 'focus', 'Ano')).toContain('2026');
    expect(
      valor('banco_central', 'focus', 'Anos com previsão')
    ).toBeUndefined();
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
    // Sem os traços da tabela, e o código de 8 dígitos (o da nota) antes da posição de 4.
    expect(
      valor('ncm', 'buscar', 'Resultados').startsWith(
        'Parafusos autoperfurantes, '
      )
    ).toBe(true);
    expect(valor('ncm', 'buscar', 'Primeiro da lista')).toBe(
      'Parafusos autoperfurantes'
    );
    expect(valor('ncm', 'buscar', 'Código')).toBe('7318.14.00');
    expect(
      valor('ncm', 'codigo', 'Descrição').startsWith('Outros parafusos')
    ).toBe(true);
  });

  it('F4: compras, estações e chuva com os valores', () => {
    const [primeira] = porFonte.compras_governo.compras.dados.compras;
    expect(valor('compras_governo', 'compras', 'Compras')).toContain(
      primeira.objeto
    );
    expect(valor('compras_governo', 'compras', 'Órgão')).toBe(primeira.orgao);
    expect(valor('compras_governo', 'compras', 'Primeiro da lista')).toBe(
      primeira.objeto
    );
    // A primeira compra do dado real tem o valor sigiloso (0 no PNCP): o servidor tira o campo, e a linha não aparece.
    expect(primeira.valor_estimado).toBeUndefined();
    expect(
      valor('compras_governo', 'compras', 'Valor estimado (R$)')
    ).toBeUndefined();
    expect(valor('estacoes', 'estacoes', 'Estações')).toContain('UBERLANDIA');
    expect(valor('estacoes', 'estacoes', 'Distância (km)')).toBe('2');
    expect(valor('estacoes', 'estacoes', 'Situação')).toBe('Operante');
    expect(valor('chuva', 'chuva', 'Chuva no período (mm)')).toBe('64,4');
    // Vários dias (lista sem nome, um campo só além da data): cada dia com a chuva dele, numa linha com o rótulo do
    // campo; o rótulo da lista ("Dias") não aparece.
    const dia = d => new Date(2026, 10, d).toLocaleDateString('pt-BR');
    expect(valor('chuva', 'chuva', 'Chuva no dia (mm)')).toBe(
      `${dia(4)}: 0,9 · ${dia(5)}: 6,2 · ${dia(6)}: 0,9 · e mais 4`
    );
    expect(valor('chuva', 'chuva', 'Dias')).toBeUndefined();
    expect(valor('chuva', 'chuva', 'Primeiro da lista')).toBeUndefined();
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

  // F5: as bases que a plataforma baixa (dado real gravado por script/ferramentas_prontas/gravar_dados_reais_das_bases.rb).
  // Toda base mostra a data em que foi atualizada: é o que diz ao dono se o dado ainda vale.
  const diaF5 = (ano, mes, d) =>
    new Date(ano, mes - 1, d).toLocaleDateString('pt-BR');

  it('F5 ANS: operadora com registro, situação e tipo; a cancelada com data e motivo', () => {
    expect(valor('planos_de_saude', 'operadora', 'Operadoras')).toBe(
      'UNIMED CAMPINAS - COOPERATIVA DE TRABALHO MÉDICO'
    );
    // Registro é chave de identificação: sem milhar.
    expect(valor('planos_de_saude', 'operadora', 'Registro na ANS')).toBe(
      '335690'
    );
    // CNPJ com a máscara, como no card Dados da empresa (e sem milhar: é chave de identificação).
    expect(valor('planos_de_saude', 'operadora', 'CNPJ')).toBe(
      '46.124.624/0001-11'
    );
    expect(valor('planos_de_saude', 'operadora_cancelada', 'CNPJ')).toBe(
      '22.869.997/0001-53'
    );
    expect(valor('planos_de_saude', 'operadora', 'Situação')).toBe('ativa');
    expect(valor('planos_de_saude', 'operadora', 'Tipo de operadora')).toBe(
      'Cooperativa Médica'
    );
    expect(valor('planos_de_saude', 'operadora', 'Base atualizada em')).toBe(
      diaF5(2026, 11, 11)
    );
    expect(valor('planos_de_saude', 'operadora_cancelada', 'Situação')).toBe(
      'cancelada'
    );
    expect(
      valor('planos_de_saude', 'operadora_cancelada', 'Cancelada em')
    ).toBe(diaF5(2026, 11, 5));
    expect(
      valor('planos_de_saude', 'operadora_cancelada', 'Motivo do cancelamento')
    ).toBe('INEXISTÊNCIA DE PRODUTO ATIVO POR MAIS DE 180 DIAS');
  });

  it('F5 ANAC: aeronave pela matrícula, com situação, certificado, gravames e empresas', () => {
    expect(valor('aeronaves', 'aeronave', 'Matrícula')).toBe('PPAAD');
    expect(valor('aeronaves', 'aeronave', 'Fabricante')).toBe(
      'CESSNA AIRCRAFT'
    );
    expect(valor('aeronaves', 'aeronave', 'Modelo')).toBe('680');
    expect(valor('aeronaves', 'aeronave', 'Situação')).toBe('registrada');
    expect(
      valor(
        'aeronaves',
        'aeronave',
        'Certificado de aeronavegabilidade válido até'
      )
    ).toBe(diaF5(2029, 10, 30));
    expect(valor('aeronaves', 'aeronave', 'Gravames (ônus registrados)')).toBe(
      'INTERCÂMBIO OPERACIONAL'
    );
    expect(valor('aeronaves', 'aeronave', 'Empresas proprietárias')).toBe(
      'AVIACAO EXEMPLO 1 LTDA'
    );
    expect(valor('aeronaves', 'aeronave', 'Empresas operadoras')).toBe(
      'AVIACAO EXEMPLO 1 LTDA e AVIACAO EXEMPLO 2 LTDA'
    );
    expect(valor('aeronaves', 'aeronave', 'Base atualizada em')).toBe(
      diaF5(2026, 11, 11)
    );
  });

  it('F5 ANEEL: placas solares da cidade e do CEP, com o total e os sistemas de cada tipo de consumidor', () => {
    expect(valor('geracao_solar', 'cidade', 'Cidade')).toBe('Campinas');
    expect(valor('geracao_solar', 'cidade', 'Estado')).toBe('SP');
    expect(
      valor('geracao_solar', 'cidade', 'Total de sistemas instalados')
    ).toBe('18.164');
    expect(valor('geracao_solar', 'cidade', 'Potência total (kW)')).toBe(
      '143.834,24'
    );
    // Cada tipo de consumidor com os sistemas dele, numa linha só.
    expect(
      valor('geracao_solar', 'cidade', 'Sistemas por tipo de consumidor')
    ).toBe(
      'Residencial: 16.577 · Comercial: 1.332 · Industrial: 107 · e mais 5'
    );
    // Cada rótulo aparece uma vez: o total não se repete no detalhe (só solar: sem a linha por tipo de geração).
    const rotulos = linhas('geracao_solar', 'cidade').map(([rotulo]) => rotulo);
    expect(rotulos.length).toBe(new Set(rotulos).size);
    expect(
      valor('geracao_solar', 'cidade', 'Sistemas por tipo de geração')
    ).toBeUndefined();
    expect(
      valor('geracao_solar', 'cidade', 'Primeiro da lista')
    ).toBeUndefined();
    // CEP é chave de identificação: sem milhar.
    expect(valor('geracao_solar', 'cep', 'CEP')).toBe('41300400');
    expect(valor('geracao_solar', 'cep', 'Total de sistemas instalados')).toBe(
      '2.373'
    );
    expect(valor('geracao_solar', 'cep', 'Potência total (kW)')).toBe(
      '54.977,7'
    );
    expect(
      valor('geracao_solar', 'cep', 'Sistemas por tipo de consumidor')
    ).toBe('Comercial: 1.478 · Residencial: 691 · Industrial: 92 · e mais 3');
    expect(valor('geracao_solar', 'cep', 'Base atualizada em')).toBe(
      diaF5(2026, 11, 11)
    );
  });

  it('F5 ANTT: transportadora com RNTRC, situação e equiparação; pelo nome, a lista com o total', () => {
    // RNTRC é chave de identificação: os zeros da frente ficam e não há milhar.
    expect(valor('transportadoras', 'registro', 'RNTRC')).toBe('000000001');
    expect(valor('transportadoras', 'registro', 'Registros')).toBe(
      'TRANSPORTADORA EXEMPLO 1 LTDA'
    );
    expect(valor('transportadoras', 'registro', 'CNPJ')).toBe(
      '11.222.333/0001-81'
    );
    expect(valor('transportadoras', 'registro', 'Situação')).toBe('ativo');
    expect(
      valor('transportadoras', 'registro', 'Equiparada a autônomo (TAC)')
    ).toBe('S');
    expect(valor('transportadoras', 'registro', 'Base atualizada em')).toBe(
      diaF5(2026, 11, 11)
    );
    expect(valor('transportadoras', 'registro_pelo_nome', 'Registros')).toBe(
      'TRANSPORTADORA EXEMPLO 1 LTDA, TRANSPORTADORA EXEMPLO 2 LTDA, TRANSPORTADORA EXEMPLO 3 LTDA e mais 153'
    );
    expect(
      valor('transportadoras', 'registro_pelo_nome', 'Primeiro da lista')
    ).toBe('TRANSPORTADORA EXEMPLO 1 LTDA');
  });

  it('F5 INPE: focos de queimada no lugar, no período, por dia, o último e o mais perto', () => {
    expect(valor('queimadas', 'focos', 'Onde')).toBe('Almeirim (PA)');
    expect(valor('queimadas', 'focos', 'Focos no período')).toBe('1.258');
    // Regra B: cada dia com os focos dele, numa linha com o rótulo do campo; o rótulo da lista não aparece.
    expect(valor('queimadas', 'focos', 'Focos no dia')).toBe(
      `${diaF5(2026, 11, 11)}: 385 · ${diaF5(2026, 11, 10)}: 873`
    );
    expect(valor('queimadas', 'focos', 'Dias com focos')).toBeUndefined();
    // Data com hora, sem conversão de fuso (regra C).
    const horario = new Date(2026, 10, 11, 11, 10).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
    expect(valor('queimadas', 'focos', 'Último foco detectado em')).toBe(
      `${diaF5(2026, 11, 11)} ${horario}`
    );
    expect(
      valor('queimadas', 'focos', 'Distância do foco mais perto (km)')
    ).toBe('6,4');
    // A lista dos últimos focos (coordenada e bioma) não vai: na tela ela era só a contagem.
    expect(valor('queimadas', 'focos', 'Focos mais recentes')).toBeUndefined();
    expect(valor('queimadas', 'focos', 'Base atualizada em')).toBe(
      diaF5(2026, 11, 11)
    );
  });

  // A saída inteira das listas que já enganaram: o detalhe do primeiro item parecia valer para todos ("Situação:
  // Suspenso" depois dos corretores, "Código: 1" depois das marcas, "Estado: AC" depois dos estados).
  // C27: lista sem rótulo não aparece. As listas do banco por nome e do CEP por endereço precisam do rótulo no i18n,
  // senão o banco e o endereço de um resultado só sumiam da tela (varredura: bancos/por_nome, cep/por_endereco).
  it('o banco por nome e o CEP por endereço de um resultado só aparecem com o rótulo da lista', () => {
    const banco = linhasDoResultado(
      {
        total: 1,
        bancos: [
          {
            codigo: '341',
            nome: 'ITAÚ UNIBANCO S.A.',
            nome_completo: 'ITAÚ UNIBANCO S.A.',
            ispb: '60701190',
          },
        ],
      },
      PT
    );
    expect(banco).toEqual([
      ['Bancos', 'ITAÚ UNIBANCO S.A.'],
      ['Código', '341'],
    ]);
    const endereco = linhasDoResultado(
      {
        cidade: 'São José',
        uf: 'SC',
        total: 1,
        ceps: [
          { cep: '88104-480', logradouro: 'Rua das Flores', bairro: 'Centro' },
        ],
      },
      PT
    );
    expect(endereco).toEqual([
      ['Cidade', 'São José'],
      ['Estado', 'SC'],
      ['CEP', '88104-480'],
      ['Rua', 'Rua das Flores'],
      ['Bairro', 'Centro'],
    ]);
    expect(
      linhasDoResultado({ bancos: [{ nome: 'X', codigo: '1' }] }, EN)[0][0]
    ).toBe('Banks');
    expect(
      linhasDoResultado({ ceps: [{ cep: '1', logradouro: 'R' }] }, EN)
    ).toEqual([
      ['ZIP code', '1'],
      ['Street', 'R'],
    ]);
  });

  it('saída completa: corretores, marcas, estados e feriados', () => {
    const dia = (ano, mes, d) =>
      new Date(ano, mes - 1, d).toLocaleDateString('pt-BR');
    expect(linhas('corretor_susep', 'por_nome')).toEqual([
      [
        'Corretores',
        'CORRETORA EXEMPLO 1 LTDA, CORRETORA EXEMPLO 2 LTDA, CORRETORA EXEMPLO 3 LTDA e mais 225',
      ],
      ['Primeiro da lista', 'CORRETORA EXEMPLO 1 LTDA'],
      ['Situação', 'Suspenso'],
      ['Registro na SUSEP', '100000001'],
    ]);
    // O código da marca é chave de identificação: não vira par, a lista mostra só os nomes.
    expect(linhas('fipe', 'marcas')).toEqual([
      ['Marcas', 'Acura, Agrale, Alfa Romeo e mais 105'],
    ]);
    expect(linhas('cidades', 'estados')).toEqual([
      ['Estados', 'Acre, Alagoas, Amapá e mais 24'],
    ]);
    expect(linhas('feriados', 'feriados')).toEqual([
      ['Ano', '2026'],
      [
        'Feriados',
        `Confraternização mundial: ${dia(2026, 1, 1)} · Carnaval: ${dia(2026, 2, 16)} · Carnaval: ${dia(2026, 2, 17)} · e mais 11`,
      ],
      ['Observação', porFonte.feriados.feriados.dados.observacao],
    ]);
  });
});
