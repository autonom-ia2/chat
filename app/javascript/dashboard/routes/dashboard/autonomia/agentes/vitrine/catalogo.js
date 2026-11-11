// #2858 F2 — vitrine de ferramentas prontas: o que a tela sabe de cada fonte do catálogo do servidor
// (Autonomia::FerramentasProntas::Catalogo). `id` é a chave do servidor; os textos ficam no i18n em
// AGENTS.VITRINE.FERRAMENTAS.<ID EM MAIÚSCULAS>. Aqui só o que não é frase: ícone, grupo, quantas perguntas a mesma
// ferramenta responde (o agente escolhe a consulta pela conversa) e os ramos em que o cartão fica em destaque. A
// vitrine mostra só os cartões cujas chaves o servidor mandou em `fontes` (as flags da conta decidem).

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

// A data de exemplo da contagem de dias úteis: daqui a 20 dias (sempre no futuro, dentro do limite de dois anos).
const DIAS_DO_EXEMPLO = 20;

// `consultas`: quantas perguntas diferentes a fonte responde no servidor (o agente escolhe).
// `ramos`: camadas do pacote da conta (#1550) em que o cartão aparece em destaque.
// `semCampo`: o "Experimente" não pede valor (o servidor responde o dólar do dia).
// `exemplo`: o valor de exemplo que muda com o tempo (a data final da contagem de dias úteis); sem ele, o do i18n.
// `base`: a fonte é uma base que a plataforma baixa (F5); o cartão diz de quando é a cópia.
export const FERRAMENTAS = [
  { id: 'cnpj', grupo: 'PESSOAS', icone: 'i-lucide-building-2' },
  {
    id: 'cpf',
    grupo: 'PESSOAS',
    icone: 'i-lucide-id-card',
    ramos: ['seguros'],
  },
  { id: 'cep', grupo: 'LUGAR', icone: 'i-lucide-map-pin', ramos: ['seguros'] },
  { id: 'cidades', grupo: 'LUGAR', icone: 'i-lucide-landmark', consultas: 2 },
  { id: 'localizacao', grupo: 'LUGAR', icone: 'i-lucide-locate-fixed' },
  { id: 'ddd', grupo: 'LUGAR', icone: 'i-lucide-phone' },
  {
    id: 'fipe',
    grupo: 'VEICULOS',
    icone: 'i-lucide-car',
    consultas: 3,
    ramos: ['seguros'],
  },
  {
    id: 'banco_central',
    grupo: 'DINHEIRO',
    icone: 'i-lucide-trending-up',
    consultas: 4,
    semCampo: true,
  },
  {
    id: 'feriados',
    grupo: 'DINHEIRO',
    icone: 'i-lucide-calendar-days',
    consultas: 2,
    exemplo: hoje => {
      const data = new Date(hoje);
      data.setDate(data.getDate() + DIAS_DO_EXEMPLO);
      const doisDigitos = numero => String(numero).padStart(2, '0');
      const dia = doisDigitos(data.getDate());
      const mes = doisDigitos(data.getMonth() + 1);
      return `${dia}/${mes}/${data.getFullYear()}`;
    },
  },
  { id: 'bancos', grupo: 'DINHEIRO', icone: 'i-lucide-banknote' },
  // F4 (flag `agente_ferramentas_prontas_lote2`)
  { id: 'hospitais', grupo: 'SAUDE', icone: 'i-lucide-hospital' },
  {
    id: 'procedimentos',
    grupo: 'SAUDE',
    icone: 'i-lucide-stethoscope',
    consultas: 2,
  },
  { id: 'doencas', grupo: 'SAUDE', icone: 'i-lucide-book-open', consultas: 2 },
  { id: 'estacoes', grupo: 'CLIMA', icone: 'i-lucide-radio-tower' },
  { id: 'chuva', grupo: 'CLIMA', icone: 'i-lucide-cloud-rain' },
  { id: 'compras_governo', grupo: 'CLIENTES', icone: 'i-lucide-landmark' },
  {
    id: 'produtos_seguradoras',
    grupo: 'SEGUROS',
    icone: 'i-lucide-file-search',
    consultas: 2,
    ramos: ['seguros'],
  },
  {
    id: 'corretor_susep',
    grupo: 'SEGUROS',
    icone: 'i-lucide-badge-check',
    consultas: 2,
    ramos: ['seguros'],
  },
  { id: 'ncm', grupo: 'OUTROS', icone: 'i-lucide-barcode', consultas: 2 },
  // F5 (flag `agente_ferramentas_prontas_bases`): bases que a plataforma baixa e mantém atualizadas. `base`: o cartão
  // mostra o "atualizado em…" que o servidor manda.
  {
    id: 'planos_de_saude',
    grupo: 'SAUDE',
    icone: 'i-lucide-heart-handshake',
    ramos: ['seguros'],
    base: true,
  },
  { id: 'aeronaves', grupo: 'VEICULOS', icone: 'i-lucide-plane', base: true },
  {
    id: 'transportadoras',
    grupo: 'VEICULOS',
    icone: 'i-lucide-truck',
    ramos: ['seguros'],
    base: true,
  },
  {
    id: 'geracao_solar',
    grupo: 'LUGAR',
    icone: 'i-lucide-sun',
    consultas: 2,
    base: true,
  },
  { id: 'queimadas', grupo: 'CLIMA', icone: 'i-lucide-flame', base: true },
];

// Sem pacote na conta: as que servem a quase todo negócio.
export const MAIS_ESCOLHIDAS = ['cep', 'cnpj', 'feriados', 'banco_central'];

// A chave do i18n: "banco_central" -> "BANCO_CENTRAL".
export const chaveDoTexto = id => String(id).toUpperCase();

export const ferramentaPorId = id => FERRAMENTAS.find(item => item.id === id);

// As do catálogo que o servidor liberou para a conta, na ordem da vitrine.
export const liberadas = chaves =>
  FERRAMENTAS.filter(item => chaves.includes(item.id));

// Destaque pelo ramo da conta (camadas do pacote, #1550): a conta de corretora vê o que vale para "seguros".
export const emDestaque = (ferramentas, camadas) => {
  if (!camadas.length) {
    return ferramentas.filter(item => MAIS_ESCOLHIDAS.includes(item.id));
  }
  return ferramentas.filter(item =>
    (item.ramos || []).some(ramo => camadas.includes(ramo))
  );
};
