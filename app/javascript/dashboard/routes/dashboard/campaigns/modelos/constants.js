// Modelos de mensagem do WhatsApp — o que a tela mostra a partir dos dados.
// Os textos moram no i18n (MODELOS_WHATSAPP.*); aqui ficam só chaves, ícones e
// classes de cor escritas por inteiro, para o Tailwind encontrá-las.

// Objetivos da galeria "Começar pronto". O texto de cada um está em
// MODELOS_WHATSAPP.OBJETIVOS.<chave>.TEXTO, com os campos escritos [assim].
export const OBJETIVOS = [
  {
    chave: 'boas_vindas',
    icone: 'i-lucide-hand-heart',
    tom: 'bg-n-blue-3 text-n-blue-11',
    tipo: 'divulgacao',
    botoes: [{ tipo: 'resposta', chaveTexto: 'QUERO_SABER_MAIS' }],
  },
  {
    chave: 'lembrete',
    icone: 'i-lucide-calendar-clock',
    tom: 'bg-n-teal-3 text-n-teal-11',
    tipo: 'aviso',
    botoes: [
      { tipo: 'resposta', chaveTexto: 'CONFIRMO' },
      { tipo: 'resposta', chaveTexto: 'REMARCAR' },
    ],
  },
  {
    chave: 'pesquisa',
    icone: 'i-lucide-star',
    tom: 'bg-n-amber-3 text-n-amber-11',
    tipo: 'aviso',
    botoes: [
      { tipo: 'resposta', chaveTexto: 'OTIMO' },
      { tipo: 'resposta', chaveTexto: 'BOM' },
      { tipo: 'resposta', chaveTexto: 'PODE_MELHORAR' },
    ],
  },
  {
    chave: 'promocao',
    icone: 'i-lucide-tag',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
    tipo: 'divulgacao',
    botoes: [
      // Sem endereço de fábrica: cada empresa escreve o do próprio site, e a
      // conferência não deixa enviar sem ele.
      { tipo: 'site', chaveTexto: 'VER_OFERTAS' },
    ],
  },
  {
    chave: 'cobranca',
    icone: 'i-lucide-receipt-text',
    tom: 'bg-n-violet-3 text-n-violet-11',
    tipo: 'aviso',
    // Lembrete de pagamento (#1380): só texto, aviso de serviço. Sem boleto no
    // topo (a campanha manda o mesmo arquivo para todos) e sem "Copiar código"
    // (só existe em divulgação). A segunda via vai pela conversa, uma a uma.
    botoes: [
      { tipo: 'resposta', chaveTexto: 'SEGUNDA_VIA' },
      { tipo: 'resposta', chaveTexto: 'JA_PAGUEI' },
    ],
  },
  {
    chave: 'retomar',
    icone: 'i-lucide-messages-square',
    tom: 'bg-n-iris-3 text-n-iris-11',
    tipo: 'divulgacao',
    botoes: [{ tipo: 'resposta', chaveTexto: 'QUERO_CONTINUAR' }],
  },
];

// Sem tipo: a pessoa escolhe aviso ou divulgação na etapa do texto.
export const OBJETIVO_EM_BRANCO = {
  chave: 'em_branco',
  icone: 'i-lucide-pencil-line',
  tom: 'bg-n-slate-3 text-n-slate-11',
  tipo: null,
  botoes: [],
};

// Também serve para os formatos (ícone e cor na lista); FORMATOS vem mais abaixo.
export const objetivoPorChave = chave =>
  OBJETIVOS.find(objetivo => objetivo.chave === chave) ||
  // eslint-disable-next-line no-use-before-define
  FORMATOS.find(formato => formato.chave === chave) ||
  OBJETIVO_EM_BRANCO;

// Campos que mudam para cada cliente. Rótulo e exemplo em
// MODELOS_WHATSAPP.CAMPOS.<chave>.{ROTULO,EXEMPLO}.
export const CAMPOS = [
  'nome_cliente',
  'nome_empresa',
  'data',
  'horario',
  'valor',
  'desconto',
  'link',
  'codigo',
];

export const SITUACOES = {
  pronto: {
    icone: 'i-lucide-circle-check',
    selo: 'bg-n-teal-3 text-n-teal-11',
    caixa: 'bg-n-teal-2 ring-n-teal-6',
  },
  em_analise: {
    icone: 'i-lucide-clock-3',
    selo: 'bg-n-amber-3 text-n-amber-11',
    caixa: 'bg-n-amber-2 ring-n-amber-6',
  },
  recusado: {
    icone: 'i-lucide-circle-alert',
    selo: 'bg-n-ruby-3 text-n-ruby-11',
    caixa: 'bg-n-ruby-2 ring-n-ruby-6',
  },
  pausado: {
    icone: 'i-lucide-circle-pause',
    selo: 'bg-n-slate-3 text-n-slate-11',
    caixa: 'bg-n-slate-2 ring-n-slate-6',
  },
  // DISABLED: o WhatsApp desligou depois de pausas seguidas. Não volta sozinho
  // e não dá para alterar; o caminho é duplicar e reescrever.
  desativado: {
    icone: 'i-lucide-circle-off',
    selo: 'bg-n-ruby-3 text-n-ruby-11',
    caixa: 'bg-n-ruby-2 ring-n-ruby-6',
  },
  // LIMIT_EXCEEDED: não criado, porque a conta chegou ao limite de modelos.
  limite: {
    icone: 'i-lucide-octagon-x',
    selo: 'bg-n-amber-3 text-n-amber-11',
    caixa: 'bg-n-amber-2 ring-n-amber-6',
  },
};

// Ordem da lista: o que precisa da pessoa vem primeiro.
export const ORDEM_DAS_SITUACOES = [
  'recusado',
  'limite',
  'desativado',
  'pausado',
  'em_analise',
  'pronto',
];

export const TIPOS_DE_BOTAO = [
  { chave: 'resposta', icone: 'i-lucide-reply', maximo: 10 },
  { chave: 'site', icone: 'i-lucide-external-link', maximo: 2 },
  { chave: 'ligar', icone: 'i-lucide-phone', maximo: 1 },
  { chave: 'copiar_codigo', icone: 'i-lucide-copy', maximo: 1 },
];

export const MAXIMO_DE_BOTOES = 10;

export const TOPOS = [
  { chave: 'nenhum', icone: 'i-lucide-ban' },
  { chave: 'foto', icone: 'i-lucide-image' },
  { chave: 'video', icone: 'i-lucide-video' },
  { chave: 'documento', icone: 'i-lucide-file-text' },
];

export const LIMITE_DO_TEXTO = 1024;
export const LIMITE_DO_RODAPE = 60;

// Etapas da criação. A rota guarda a etapa na query (?etapa=).
export const ETAPAS_DA_CRIACAO = [
  'objetivo',
  'texto',
  'extras',
  'numeros',
  'confira',
];

// Rotas da jornada, para o menu acender o item "Modelos WhatsApp".
export const ROTAS_DA_JORNADA = [
  'modelos_whatsapp_lista',
  'modelos_whatsapp_novo',
  'modelos_whatsapp_enviado',
  'modelos_whatsapp_modelo',
  'modelos_whatsapp_alterar',
  'modelos_whatsapp_usar',
];

// Formatos além da mensagem comum. `soDivulgacao`: o WhatsApp só aceita o
// formato como divulgação (custo de marketing). A etapa "extras" vira a etapa
// própria do formato (cartões, oferta, catálogo, código ou formulário).
export const FORMATOS = [
  {
    chave: 'carrossel',
    icone: 'i-lucide-gallery-horizontal',
    tom: 'bg-n-blue-3 text-n-blue-11',
    tipo: 'divulgacao',
    soDivulgacao: true,
  },
  {
    chave: 'oferta',
    icone: 'i-lucide-timer',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
    tipo: 'divulgacao',
    soDivulgacao: true,
  },
  // #1418: um produto, vários numa lista ou cartões de produtos do catálogo.
  {
    chave: 'produtos',
    icone: 'i-lucide-shopping-cart',
    tom: 'bg-n-teal-3 text-n-teal-11',
    tipo: 'divulgacao',
    soDivulgacao: true,
  },
  {
    chave: 'catalogo',
    icone: 'i-lucide-shopping-bag',
    tom: 'bg-n-teal-3 text-n-teal-11',
    tipo: 'divulgacao',
    soDivulgacao: true,
    // Sem backend ainda para ler o catálogo da conta do WhatsApp.
    disponivel: false,
  },
  {
    chave: 'codigo',
    icone: 'i-lucide-key-round',
    tom: 'bg-n-violet-3 text-n-violet-11',
    tipo: 'codigo',
    soDivulgacao: false,
  },
  {
    chave: 'formulario',
    icone: 'i-lucide-clipboard-list',
    tom: 'bg-n-amber-3 text-n-amber-11',
    tipo: 'aviso',
    soDivulgacao: false,
    // Sem backend ainda para listar os formulários (Flows) da conta.
    disponivel: false,
  },
];

export const formatoPorChave = chave =>
  FORMATOS.find(formato => formato.chave === chave) || null;

export const LIMITE_DO_TEXTO_DA_OFERTA = 600;
// #1418: texto de um produto só (SPM) e título da lista de vários (MPM), da Meta.
export const LIMITE_DO_TEXTO_DE_UM_PRODUTO = 160;
export const LIMITE_DO_TITULO_DOS_PRODUTOS = 60;
// Como os produtos aparecem: um, vários numa lista ou cartões lado a lado.
export const JEITOS_DE_MOSTRAR_PRODUTOS = ['um', 'varios', 'carrossel'];
export const LIMITE_DO_TITULO_DA_OFERTA = 16;
export const LIMITE_DO_CARTAO = 160;
export const CARTOES_MINIMO = 2;
export const CARTOES_MAXIMO = 10;
export const BOTOES_POR_CARTAO = 2;
export const VALIDADE_MINIMA = 1;
export const VALIDADE_MAXIMA = 90;

// Código que as prévias mostram no formato "código de verificação" (não é texto
// traduzível: é só um exemplo de número).
export const CODIGO_DE_EXEMPLO = '482913';

// Sinal de qualidade que o WhatsApp dá ao modelo (quality_score da Meta), em
// palavras de gente. 'sem_nota': ainda sem retorno das pessoas (modelo novo ou
// pouco enviado). Textos em MODELOS_WHATSAPP.SAUDE.SINAIS.<chave>.
export const SINAIS = {
  bom: {
    icone: 'i-lucide-smile',
    selo: 'bg-n-teal-3 text-n-teal-11',
    caixa: 'bg-n-teal-2 ring-n-teal-6',
    cor: 'text-n-teal-11',
  },
  atencao: {
    icone: 'i-lucide-triangle-alert',
    selo: 'bg-n-amber-3 text-n-amber-11',
    caixa: 'bg-n-amber-2 ring-n-amber-6',
    cor: 'text-n-amber-11',
  },
  ruim: {
    icone: 'i-lucide-octagon-alert',
    selo: 'bg-n-ruby-3 text-n-ruby-11',
    caixa: 'bg-n-ruby-2 ring-n-ruby-6',
    cor: 'text-n-ruby-11',
  },
  sem_nota: {
    icone: 'i-lucide-hourglass',
    selo: 'bg-n-slate-3 text-n-slate-11',
    caixa: 'bg-n-slate-2 ring-n-slate-6',
    cor: 'text-n-slate-11',
  },
};

// Sinais que pedem ação da pessoa: a lista mostra o selo e sobe o modelo.
export const SINAIS_DE_ALERTA = ['ruim', 'atencao'];
