// #2692 — dados da demonstração da Prospecção nova. Tudo inventado: empresas,
// pessoas, telefones e CNPJs não existem. Só é carregado no ambiente de
// desenvolvimento (acharFonte.js, `import.meta.env.DEV`); em produção o arquivo
// nem entra no pacote.
//
// Uma fonte só de números para a demonstração inteira (rodada 2): a porta pede
// "até 20 empresas" e a busca acha 20 = 16 que podem ir (1 "Chame primeiro" +
// 6 boa · 5 média · 4 pouca) + 4 que ficam de fora (2 já no funil, 1 não quer
// mensagem, 1 fechou). Na jornada a pessoa tira 2: vão 14. Das 14, 2 não têm
// celular nem e-mail, então a lista de mensagem fica com 12. Depois de mandar,
// a busca tem 16 no funil (as 2 que já estavam + as 14). Na fila, 2 vão para o
// funil e 1 volta amanhã. Todos os textos da tela saem destes dados.

export const LIMITE = 20;

export const LUGAR_SALVO = {
  rotulo: 'Centro, Campinas, SP',
  placeId: 'demo-centro-campinas',
};

export const SUGESTOES = [
  { placeId: 'demo-centro-campinas', rotulo: 'Centro, Campinas, SP' },
  { placeId: 'demo-centro-valinhos', rotulo: 'Centro, Valinhos, SP' },
  { placeId: 'demo-centro-sumare', rotulo: 'Centro, Sumaré, SP' },
];

export const SUGESTAO_UNICA = [
  { placeId: 'demo-barao-geraldo', rotulo: 'Barão Geraldo, Campinas, SP' },
];

export const FUNIS = [
  {
    id: 101,
    nome: 'Vendas',
    venda: true,
    etapas: [
      { id: 1001, nome: 'Novo contato' },
      { id: 1002, nome: 'Conversando' },
      { id: 1003, nome: 'Proposta' },
      { id: 1004, nome: 'Fechado' },
    ],
  },
  {
    id: 102,
    nome: 'Atendimento',
    venda: false,
    etapas: [{ id: 1101, nome: 'Aberto' }],
  },
];

// Um segundo funil de vendas, para o painel "Para onde vão" ter escolha.
export const FUNIL_REVENDA = {
  id: 103,
  nome: 'Revenda',
  venda: true,
  etapas: [
    { id: 1201, nome: 'Primeiro contato' },
    { id: 1202, nome: 'Negociando' },
  ],
};

export const PESSOAS = [
  { id: 'voce', nome: 'John', voce: true },
  { id: 7, nome: 'Lucas Andrade' },
  { id: 8, nome: 'Paula Ribeiro' },
  { id: 9, nome: 'Diego Martins' },
];

// Os modelos salvos da conta ("Seus modelos", v4 T0p).
export const MODELOS = [
  { id: 'modelo-1', nome: 'Bem avaliadas com telefone' },
  { id: 'modelo-2', nome: 'Abertas no sábado' },
];

const fixo = n => `(19) 3000-${String(100 + n).padStart(4, '0')}`;
const celular = n => `(19) 9 9${String(100 + n).padStart(3, '0')}-4567`;
const telefoneDe = (n, whatsapp) => (whatsapp === 'tem' ? celular(n) : fixo(n));

// [nome, categoria, bairro, prioridade, porquê, dono (estado, nome, cargo),
//  whatsapp, tem celular ou e-mail]
const BASE = [
  [
    'Contabilidade Horizonte',
    'Escritório de contabilidade',
    'Centro',
    96,
    'Nota boa e muitas avaliações no Google.',
    ['confirmado', 'Maria Souza', 'sócia'],
    'tem',
    true,
  ],
  [
    'Prado & Lima Advogados',
    'Escritório de advocacia',
    'Centro',
    91,
    'Tem telefone e mostra horário.',
    ['confirmado', 'Carlos Prado', 'sócio'],
    'tem',
    true,
  ],
  [
    'Estúdio Traço Arquitetura',
    'Escritório de arquitetura',
    'Bosque',
    87,
    'Muitas avaliações e responde no Google.',
    ['possivel', 'Renata Traço', 'arquiteta'],
    'tem',
    true,
  ],
  [
    'Ponto Certo Contadores',
    'Escritório de contabilidade',
    'Centro',
    84,
    'Nota boa e site no ar.',
    ['confirmado', 'José Almeida', 'sócio'],
    'sem',
    true,
  ],
  [
    'Rede Coworking Campinas',
    'Coworking',
    'Centro',
    80,
    'Aberta agora e com muitas fotos.',
    ['confirmado', 'Ana Ferraz', 'sócia'],
    'tem',
    true,
  ],
  [
    'Moraes Engenharia',
    'Escritório de engenharia',
    'Botafogo',
    74,
    'Tem telefone e nota boa.',
    ['nenhum', '', ''],
    'tem',
    true,
  ],
  [
    'Atlas Consultoria Empresarial',
    'Consultoria',
    'Centro',
    69,
    'Muitas avaliações no Google.',
    ['confirmado', 'Paulo Atlas', 'sócio'],
    'sem',
    true,
  ],
  [
    'Nogueira Topografia',
    'Escritório de topografia',
    'Vila Itapura',
    47,
    'Poucas avaliações, mas nota boa.',
    ['nenhum', '', ''],
    'sem',
    true,
  ],
  [
    'Escritório Dois Rios',
    'Escritório de advocacia',
    'Centro',
    44,
    'Tem telefone e site.',
    ['possivel', 'Marta Rios', 'advogada'],
    'tem',
    true,
  ],
  [
    'Soluções RH Campinas',
    'Consultoria de RH',
    'Centro',
    39,
    'Mostra horário no Google.',
    ['confirmado', 'Felipe Costa', 'sócio'],
    'sem',
    false,
  ],
  [
    'Grão Fino Traduções',
    'Escritório de traduções',
    'Guanabara',
    34,
    'Poucas fotos e sem site.',
    ['nenhum', '', ''],
    'sem',
    false,
  ],
  [
    'Marques Assessoria',
    'Assessoria empresarial',
    'Centro',
    30,
    'Tem telefone.',
    ['confirmado', 'Rita Marques', 'sócia'],
    'tem',
    true,
  ],
  [
    'Escritório Alvorada',
    'Escritório de contabilidade',
    'Jardim Chapadão',
    21,
    'Poucas avaliações no Google.',
    ['nenhum', '', ''],
    'sem',
    true,
  ],
  [
    'Cópias & Cia',
    'Serviços de escritório',
    'Centro',
    17,
    'Sem site e com poucas fotos.',
    ['nenhum', '', ''],
    'tem',
    true,
  ],
  [
    'Vértice Agrimensura',
    'Escritório de agrimensura',
    'Ponte Preta',
    12,
    'Quase não aparece no Google.',
    ['nenhum', '', ''],
    'sem',
    true,
  ],
  [
    'Escritório São Bento',
    'Escritório de advocacia',
    'Centro',
    8,
    'Sem telefone no Google.',
    ['nenhum', '', ''],
    'sem',
    true,
  ],
];

// [nome, categoria, bairro, prioridade, porquê, motivo de ficar de fora]
const FORA = [
  [
    'Lima Contábil',
    'Escritório de contabilidade',
    'Centro',
    88,
    'Nota boa e muitas avaliações no Google.',
    { motivo: 'no_funil', funil: 'Vendas' },
  ],
  [
    'Arquitetura Sol Nascente',
    'Escritório de arquitetura',
    'Cambuí',
    72,
    'Muitas fotos e site no ar.',
    { motivo: 'no_funil', funil: 'Vendas' },
  ],
  [
    'Fontes Consultoria',
    'Consultoria',
    'Centro',
    55,
    'Tem telefone e mostra horário.',
    { motivo: 'nao_quer' },
  ],
  [
    'Escritório Boa Vista',
    'Escritório de advocacia',
    'Centro',
    33,
    'Aparece pouco no Google.',
    { motivo: 'fechou' },
  ],
];

// As 2 que a pessoa tira na jornada (confira-tirou): ficam na dobra, para o
// "Não vai" aparecer na tela.
export const TIRADAS_NA_JORNADA = [2, 3];

const chance = prioridade => {
  if (prioridade >= 50) return 'boa';
  if (prioridade >= 25) return 'media';
  return 'pouca';
};

// Pontos inventados em volta do centro de Campinas, só para o mapa ter onde
// pôr os pinos (a demo não tem chave do Google, então o mapa não desenha).
const CENTRO = { lat: -22.9056, lng: -47.0608 };
const pontoDe = id => ({
  latitude: CENTRO.lat + (((id * 37) % 21) - 10) * 0.0012,
  longitude: CENTRO.lng + (((id * 53) % 21) - 10) * 0.0014,
});

// Os outros sócios achados na pesquisa, sem o dono atual ("Falar com outra
// pessoa"). Quem não tem outro sócio não mostra o botão.
const OUTROS_SOCIOS = {
  1: [
    { nome: 'Pedro Henrique Dias', cargo: 'sócio' },
    { nome: 'Luiza Souza', cargo: 'sócia' },
  ],
  2: [{ nome: 'Beatriz Lima', cargo: 'sócia' }],
  3: [{ nome: 'Paulo Traço', cargo: 'sócio' }],
  5: [{ nome: 'Rafael Ferraz', cargo: 'sócio' }],
};

const empresaBase = (linha, indice) => {
  const [nome, categoria, bairro, prioridade, porque, dono, whatsapp, contato] =
    linha;
  const id = indice + 1;
  return {
    id,
    nome,
    categoria,
    bairro,
    endereco: `Rua das Flores, ${100 + id * 7} · ${bairro}, Campinas`,
    ...pontoDe(id),
    prioridade,
    chance: chance(prioridade),
    porque,
    dono: { estado: dono[0], nome: dono[1], cargo: dono[2] },
    socios: OUTROS_SOCIOS[id] || [],
    whatsapp,
    whatsappUrl: null,
    telefone: telefoneDe(id, whatsapp),
    site: `www.empresa${id}-exemplo.com.br`,
    email: '',
    nota: Math.round((3.4 + (prioridade / 100) * 1.5) * 10) / 10,
    avaliacoes: Math.round(prioridade / 2) + 3,
    cnpj: `00.000.${String(100 + id).padStart(3, '0')}/0001-00`,
    situacao: 'Ativa',
    noFunil: null,
    fora: null,
    temContato: contato,
  };
};

const empresaFora = (linha, indice) => {
  const [nome, categoria, bairro, prioridade, porque, fora] = linha;
  const base = empresaBase(
    [
      nome,
      categoria,
      bairro,
      prioridade,
      porque,
      ['nenhum', '', ''],
      'sem',
      true,
    ],
    BASE.length + indice
  );
  return {
    ...base,
    fora,
    situacao: fora.motivo === 'fechou' ? 'Baixada' : 'Ativa',
    noFunil:
      fora.motivo === 'no_funil'
        ? { funil: 'Vendas', etapa: 'Conversando', pessoa: 'Lucas Andrade' }
        : null,
  };
};

export const empresas = () => [
  ...BASE.map(empresaBase),
  ...FORA.map(empresaFora),
];

// Os números que a tela mostra, todos tirados das empresas acima.
const contar = (lista, teste) => lista.filter(teste).length;
const TODAS = empresas();
const PODEM_IR = TODAS.filter(empresa => !empresa.fora);
const VAO = PODEM_IR.filter(
  empresa => !TIRADAS_NA_JORNADA.includes(empresa.id)
);
export const NUMEROS = {
  achadas: TODAS.length,
  podemIr: PODEM_IR.length,
  fora: contar(TODAS, empresa => empresa.fora),
  jaNoFunil: contar(TODAS, empresa => empresa.fora?.motivo === 'no_funil'),
  tiradas: TIRADAS_NA_JORNADA.length,
  vao: VAO.length,
  entramNaLista: contar(VAO, empresa => empresa.temContato),
  // Depois da jornada: as que já estavam no funil + as que foram.
  noFunilDepois:
    contar(TODAS, empresa => empresa.fora?.motivo === 'no_funil') + VAO.length,
};

// "Não conseguimos trazer todas agora" (rodada 3): a busca parou em 12, da
// mesma fonte. 1 "Chame primeiro" + 4 boa + 3 média + 2 pouca = 10 podem ir, e
// 2 ficam de fora.
const PARTE_QUE_CHEGOU = { boa: 5, media: 3, pouca: 2 };
export const empresasGoogleParou = () => {
  const lista = empresas();
  const daChance = chave =>
    lista
      .filter(empresa => !empresa.fora && empresa.chance === chave)
      .slice(0, PARTE_QUE_CHEGOU[chave]);
  return [
    ...daChance('boa'),
    ...daChance('media'),
    ...daChance('pouca'),
    ...lista.filter(empresa => empresa.fora).slice(0, 2),
  ];
};

// Os donos e o WhatsApp ainda chegando: as primeiras 8 já resolvidas, o resto
// procurando (a página resolve uma por vez, como o evento ao vivo). As que
// ficam de fora já vêm resolvidas: não entram na pesquisa.
export const empresasChegando = () =>
  empresas().map((empresa, indice) =>
    indice < 8 || empresa.fora
      ? empresa
      : {
          ...empresa,
          dono: { estado: 'procurando', nome: '', cargo: '' },
          whatsapp: 'conferindo',
        }
  );

// Uma busca de 40 (o pedido "Até 40"), para o campo "Procurar pelo nome".
export const empresasMuitas = () => {
  const lista = empresas();
  const extras = [...BASE, ...BASE]
    .slice(0, 40 - lista.length)
    .map((linha, indice) =>
      empresaBase(
        [
          `${linha[0]} ${indice < BASE.length ? 'Filial' : 'Norte'}`,
          ...linha.slice(1),
        ],
        lista.length + indice
      )
    );
  return [...lista, ...extras];
};

const HOJE = 0;
export const BUSCAS = [
  {
    id: 'demo',
    oQue: 'Escritórios',
    lugar: 'Centro, Campinas, SP',
    achadas: NUMEROS.achadas,
    noFunil: NUMEROS.noFunilDepois,
    diasAtras: HOJE,
    feitaPor: null,
  },
  {
    id: 'demo-padarias',
    oQue: 'Padarias',
    lugar: 'Taquaral, Campinas, SP',
    achadas: 18,
    noFunil: 4,
    diasAtras: 1,
    feitaPor: 'Lucas Andrade',
    feitaPorId: 7,
  },
  {
    id: 'demo-academias',
    oQue: 'Academias',
    lugar: 'Cambuí, Campinas, SP',
    achadas: 20,
    noFunil: 9,
    diasAtras: 3,
    feitaPor: 'Paula Ribeiro',
    feitaPorId: 8,
  },
  {
    id: 'demo-oficinas',
    oQue: 'Oficinas',
    lugar: 'Vila Industrial, Campinas, SP',
    achadas: 15,
    noFunil: 2,
    diasAtras: 6,
    feitaPor: null,
  },
  {
    id: 'demo-lojas',
    oQue: 'Lojas de roupa',
    lugar: 'Centro, Valinhos, SP',
    achadas: 20,
    noFunil: 0,
    diasAtras: 9,
    feitaPor: 'Diego Martins',
    feitaPorId: 9,
  },
];

export const FILA = [
  {
    id: 201,
    nome: 'Padaria Pão Quente',
    categoria: 'Padaria',
    bairro: 'Taquaral',
    endereco: 'Av. Brasil, 1200 · Taquaral, Campinas',
    chance: 'boa',
    porque: 'Nota boa e muitas avaliações no Google.',
    dono: { estado: 'confirmado', nome: 'Antônio Ramos', cargo: 'sócio' },
    whatsapp: 'tem',
    telefone: celular(201),
    site: 'www.paoquente-exemplo.com.br',
    nota: 4.7,
    avaliacoes: 212,
    achadoPor: 'Lucas Andrade',
  },
  {
    id: 202,
    nome: 'Academia Corpo Ativo',
    categoria: 'Academia',
    bairro: 'Cambuí',
    endereco: 'Rua Coronel Quirino, 480 · Cambuí, Campinas',
    chance: 'boa',
    porque: 'Aberta agora e com muitas fotos.',
    dono: { estado: 'possivel', nome: 'Juliana Prates', cargo: 'gerente' },
    whatsapp: 'tem',
    telefone: celular(202),
    site: 'www.corpoativo-exemplo.com.br',
    nota: 4.5,
    avaliacoes: 98,
    achadoPor: 'Paula Ribeiro',
  },
  {
    id: 203,
    nome: 'Oficina Roda Viva',
    categoria: 'Oficina mecânica',
    bairro: 'Vila Industrial',
    endereco: 'Rua Pereira Lima, 77 · Vila Industrial, Campinas',
    chance: 'media',
    porque: 'Tem telefone e mostra horário.',
    dono: { estado: 'nenhum', nome: '', cargo: '' },
    whatsapp: 'sem',
    telefone: fixo(203),
    site: '',
    nota: 4.1,
    avaliacoes: 36,
    achadoPor: 'John',
  },
  {
    id: 204,
    nome: 'Loja Fio de Linha',
    categoria: 'Loja de roupa',
    bairro: 'Centro',
    endereco: 'Rua 13 de Maio, 310 · Centro, Campinas',
    chance: 'media',
    porque: 'Muitas avaliações, mas sem site.',
    dono: { estado: 'procurando', nome: '', cargo: '' },
    whatsapp: 'conferindo',
    telefone: celular(204),
    site: '',
    nota: 4.3,
    avaliacoes: 64,
    achadoPor: 'Diego Martins',
  },
];

// O fim do dia sai da jornada da fila: Padaria e Oficina foram para o funil,
// a Academia ficou para depois (volta amanhã) e a Loja não serve.
export const FIM_DO_DIA = { foramParaOFunil: 2, voltamAmanha: 1, naoServem: 1 };

// O que já vem escrito na porta em cada estado da demonstração. `painel` abre
// "Como procurar" (como) ou "Mais ajustes" (mais) por cima.
const PADRAO = { oQue: 'Escritórios', usarSalvo: true };
export const PORTA = {
  porta: PADRAO,
  'porta-primeira': {},
  'porta-sugestoes': { oQue: 'Escritórios', ondeTexto: 'centro' },
  'porta-uma-sugestao': { oQue: 'Escritórios', ondeTexto: 'barão geraldo' },
  'porta-lugar-nao-achado': { oQue: 'Escritórios', ondeTexto: 'lugar xyz' },
  'porta-procurando': {
    oQue: 'Escritórios',
    ondeTexto: 'centro',
    procurando: true,
  },
  'porta-erro': { ...PADRAO, erro: true },
  'porta-teste': PADRAO,
  'porta-sem-google': {},
  'como-procurar': { ...PADRAO, painel: 'como' },
  'como-procurar-modelos': { ...PADRAO, painel: 'como', modelos: true },
  'mais-ajustes': { ...PADRAO, painel: 'mais', modelos: true },
  'porta-pouco-vistas': { ...PADRAO, primeiro: 'pouco' },
  // Pedido em uma frase (#2696): o campo aparece em todos os estados da porta,
  // menos sem a IA da conta.
  'porta-sem-ia': PADRAO,
  'porta-frase-erro': PADRAO,
  'porta-frase-nao-entendeu': PADRAO,
};

// Pedido em uma frase (#2696): a resposta da IA na demonstração.
export { FRASE_ENTENDIDA, FRASE_NAO_ENTENDIDA } from './acharFraseDemo';
