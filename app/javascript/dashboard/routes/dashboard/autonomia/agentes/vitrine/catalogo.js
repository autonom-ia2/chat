// #2776 — vitrine de ferramentas prontas (PROTÓTIPO). O catálogo que a plataforma oferece, em grupos de nome leigo.
// Uma fonte com várias consultas (FIPE: marca, modelo, ano e preço) é UMA ferramenta e UM cartão: o agente escolhe a
// consulta pela conversa. Arquivo público (ANTT, ANAC, ANEEL, ANS) é ferramenta também: a plataforma baixa e atualiza,
// e o cartão diz quando. Os textos ficam no i18n (AGENTS.VITRINE.FERRAMENTAS.<ID>); aqui só o que não é frase: ícone,
// grupo, ramos em destaque e o resultado FICTÍCIO do "Experimente".

export const GRUPOS = [
  { id: 'PESSOAS', icone: 'i-lucide-users', tom: 'azul' },
  { id: 'LUGAR', icone: 'i-lucide-map', tom: 'teal' },
  { id: 'VEICULOS', icone: 'i-lucide-car', tom: 'ambar' },
  { id: 'SAUDE', icone: 'i-lucide-heart-pulse', tom: 'rosa' },
  { id: 'CLIMA', icone: 'i-lucide-cloud-sun', tom: 'azul' },
  { id: 'DINHEIRO', icone: 'i-lucide-wallet', tom: 'teal' },
  { id: 'CLIENTES', icone: 'i-lucide-search-check', tom: 'violeta' },
  { id: 'SEGUROS', icone: 'i-lucide-shield-check', tom: 'azul' },
  { id: 'OUTROS', icone: 'i-lucide-shapes', tom: 'cinza' },
];

// `consultas`: quantas perguntas diferentes a mesma ferramenta responde (o agente escolhe).
// `arquivo`: a plataforma guarda uma cópia; `atualizadoEm` é a data da última cópia (fictícia).
// `ramos`: camadas do pacote da conta (#1550) em que o cartão aparece em destaque.
export const FERRAMENTAS = [
  { id: 'CNPJ', grupo: 'PESSOAS', icone: 'i-lucide-building-2', consultas: 2 },
  {
    id: 'CPF',
    grupo: 'PESSOAS',
    icone: 'i-lucide-id-card',
    ramos: ['seguros'],
  },
  { id: 'CEP', grupo: 'LUGAR', icone: 'i-lucide-map-pin', ramos: ['seguros'] },
  { id: 'IBGE', grupo: 'LUGAR', icone: 'i-lucide-landmark', consultas: 3 },
  { id: 'LOCAL', grupo: 'LUGAR', icone: 'i-lucide-locate-fixed' },
  { id: 'DDD', grupo: 'LUGAR', icone: 'i-lucide-phone' },
  {
    id: 'FIPE',
    grupo: 'VEICULOS',
    icone: 'i-lucide-car',
    consultas: 4,
    ramos: ['seguros'],
  },
  {
    id: 'CNES',
    grupo: 'SAUDE',
    icone: 'i-lucide-hospital',
    ramos: ['seguros/saude_beneficios'],
  },
  { id: 'TUSS', grupo: 'SAUDE', icone: 'i-lucide-stethoscope' },
  {
    id: 'CID',
    grupo: 'SAUDE',
    icone: 'i-lucide-clipboard-plus',
    ramos: ['seguros'],
  },
  {
    id: 'ANS',
    grupo: 'SAUDE',
    icone: 'i-lucide-heart-handshake',
    arquivo: true,
    atualizadoEm: '2026-11-09',
    ramos: ['seguros'],
  },
  { id: 'CHUVA', grupo: 'CLIMA', icone: 'i-lucide-cloud-rain' },
  { id: 'ESTACOES', grupo: 'CLIMA', icone: 'i-lucide-thermometer' },
  { id: 'QUEIMADAS', grupo: 'CLIMA', icone: 'i-lucide-flame' },
  {
    id: 'BANCO_CENTRAL',
    grupo: 'DINHEIRO',
    icone: 'i-lucide-trending-up',
    consultas: 4,
  },
  {
    id: 'FERIADOS',
    grupo: 'DINHEIRO',
    icone: 'i-lucide-calendar-days',
    consultas: 2,
  },
  { id: 'BANCOS', grupo: 'DINHEIRO', icone: 'i-lucide-banknote' },
  { id: 'LICITACOES', grupo: 'CLIENTES', icone: 'i-lucide-gavel' },
  {
    id: 'TRANSPORTADORAS',
    grupo: 'CLIENTES',
    icone: 'i-lucide-truck',
    arquivo: true,
    atualizadoEm: '2026-11-01',
  },
  {
    id: 'SOLAR',
    grupo: 'CLIENTES',
    icone: 'i-lucide-sun',
    arquivo: true,
    atualizadoEm: '2026-11-01',
  },
  {
    id: 'AERONAVES',
    grupo: 'CLIENTES',
    icone: 'i-lucide-plane',
    arquivo: true,
    atualizadoEm: '2026-11-09',
  },
  {
    id: 'SEGURADORAS',
    grupo: 'SEGUROS',
    icone: 'i-lucide-shield-check',
    consultas: 2,
    ramos: ['seguros'],
  },
  {
    id: 'SUSEP',
    grupo: 'SEGUROS',
    icone: 'i-lucide-badge-check',
    consultas: 3,
    ramos: ['seguros'],
  },
  { id: 'NCM', grupo: 'OUTROS', icone: 'i-lucide-package' },
  { id: 'DOMINIO', grupo: 'OUTROS', icone: 'i-lucide-globe' },
];

// Sem pacote na conta: as que servem a quase todo negócio.
export const MAIS_ESCOLHIDAS = ['CEP', 'CNPJ', 'FERIADOS', 'BANCO_CENTRAL'];

// O que o "Experimente" devolve no protótipo: linhas legíveis, como o teste de verdade mostra. Dados fictícios.
export const RESULTADOS = {
  CNPJ: [
    ['Empresa', 'Padaria Pão de Ouro Ltda'],
    ['Situação', 'Ativa'],
    ['Cidade', 'Campinas – SP'],
  ],
  CPF: [
    ['Situação', 'Regular'],
    ['Nome', 'Maria S. de Almeida'],
  ],
  CEP: [
    ['Rua', 'Praça da Sé'],
    ['Bairro', 'Sé'],
    ['Cidade', 'São Paulo – SP'],
  ],
  IBGE: [
    ['Cidade', 'Ribeirão Preto – SP'],
    ['População', '711.825'],
    ['Renda média', 'R$ 3.412'],
  ],
  LOCAL: [
    ['Cidade', 'Belo Horizonte – MG'],
    ['Bairro', 'Savassi'],
  ],
  DDD: [
    ['DDD', '19'],
    ['Região', 'Campinas e região – SP'],
  ],
  FIPE: [
    ['Carro', 'Chevrolet Onix LT 1.0 2020'],
    ['Valor', 'R$ 74.312'],
    ['Tabela', 'novembro de 2026'],
  ],
  CNES: [
    ['Hospital', 'Hospital Santa Clara'],
    ['Cidade', 'Curitiba – PR'],
    ['Atende', 'Pronto-socorro e maternidade'],
  ],
  TUSS: [
    ['Procedimento', 'Ressonância magnética de joelho'],
    ['Código', '41101170'],
  ],
  CID: [
    ['Código', 'J45'],
    ['Nome', 'Asma'],
  ],
  ANS: [
    ['Operadora', 'Vida Plena Saúde'],
    ['Situação', 'Ativa'],
    ['Clientes', '182.400'],
  ],
  CHUVA: [
    ['Cidade', 'Londrina – PR'],
    ['Chuva em outubro', '168 mm'],
    ['Dia mais chuvoso', '21/10'],
  ],
  ESTACOES: [
    ['Estação', 'Sorriso – MT'],
    ['Agora', '31 °C, sem chuva'],
  ],
  QUEIMADAS: [
    ['Região', 'Sinop – MT'],
    ['Focos em 7 dias', '12'],
  ],
  BANCO_CENTRAL: [
    ['Dólar hoje', 'R$ 5,42'],
    ['Juros (Selic)', '10,75% ao ano'],
    ['Inflação em 12 meses', '4,1%'],
  ],
  FERIADOS: [
    ['Data', '20/11/2026'],
    ['É feriado?', 'Sim, em São Paulo – SP'],
    ['Próximo dia útil', '23/11/2026'],
  ],
  BANCOS: [
    ['Código', '341'],
    ['Banco', 'Banco Exemplo S.A.'],
  ],
  LICITACOES: [
    ['Compra', 'Uniformes para a prefeitura'],
    ['Cidade', 'Uberlândia – MG'],
    ['Prazo', 'até 28/11/2026'],
  ],
  TRANSPORTADORAS: [
    ['Empresa', 'TransRota Cargas Ltda'],
    ['Cidade', 'Cascavel – PR'],
    ['Caminhões', '34'],
  ],
  SOLAR: [
    ['Instalações em 2026', '1.284'],
    ['Cidade', 'Petrolina – PE'],
  ],
  AERONAVES: [
    ['Matrícula', 'PR-ABC'],
    ['Modelo', 'Cessna 172'],
    ['Dono', 'Aeroclube Exemplo'],
  ],
  SEGURADORAS: [
    ['Seguradora', 'Seguradora Exemplo'],
    ['Produto', 'Auto Completo'],
    ['Cobre', 'roubo, colisão e vidros'],
  ],
  SUSEP: [
    ['Corretor', 'Ana Paula Ribeiro'],
    ['Registro', 'Ativo desde 2014'],
  ],
  NCM: [
    ['Código', '8471.30.12'],
    ['Mercadoria', 'Notebook'],
  ],
  DOMINIO: [
    ['Site', 'padariapaodeouro.com.br'],
    ['Situação', 'Registrado até 03/2027'],
  ],
};

export const ferramentaPorId = id => FERRAMENTAS.find(item => item.id === id);

// Destaque pelo ramo da conta (camadas do pacote, #1550): a conta de corretora vê o que vale para "seguros".
export const emDestaque = camadas => {
  if (!camadas.length)
    return FERRAMENTAS.filter(item => MAIS_ESCOLHIDAS.includes(item.id));
  return FERRAMENTAS.filter(item =>
    (item.ramos || []).some(ramo => camadas.includes(ramo))
  );
};
