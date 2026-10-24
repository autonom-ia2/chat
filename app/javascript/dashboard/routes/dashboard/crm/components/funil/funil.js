// #1384 — o que a gaveta de funil usa em mais de um lugar: modelos prontos,
// cores das etapas, o resumo dos retornos e o calendário das tentativas.
import { camadasDoPacote } from 'dashboard/i18n/pacotesDoPainel';
import VARIANTES from './variantes.json';

export const FUNIL = 'CRM_FUNIL';

// Cores que o Kanban já usa. A classe do selo numerado acompanha a cor; uma
// cor livre (escolhida no seletor) cai no selo azul.
export const CORES = [
  {
    valor: '#2563eb',
    nome: 'BLUE',
    amostra: 'bg-[#2563eb]',
    selo: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    valor: '#0891b2',
    nome: 'TEAL',
    amostra: 'bg-[#0891b2]',
    selo: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    valor: '#ca8a04',
    nome: 'AMBER',
    amostra: 'bg-[#ca8a04]',
    selo: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    valor: '#9333ea',
    nome: 'PURPLE',
    amostra: 'bg-[#9333ea]',
    selo: 'bg-n-violet-3 text-n-violet-11',
  },
  {
    valor: '#16a34a',
    nome: 'GREEN',
    amostra: 'bg-[#16a34a]',
    selo: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    valor: '#dc2626',
    nome: 'RED',
    amostra: 'bg-[#dc2626]',
    selo: 'bg-n-ruby-3 text-n-ruby-11',
  },
];

export const corDaPosicao = indice => CORES[indice % CORES.length].valor;

// Etapa nova ganha a primeira cor que ainda ninguém usa. Só repete quando
// todas estão em uso; aí segue a ordem pela posição.
export const corLivre = usadas => {
  const emUso = new Set(usadas.map(cor => cor?.toLowerCase()));
  return (
    CORES.find(item => !emUso.has(item.valor))?.valor ||
    corDaPosicao(usadas.length)
  );
};

export const seloDaCor = cor =>
  CORES.find(item => item.valor === cor)?.selo || 'bg-n-blue-3 text-n-blue-11';

// #1498 — a única escolha nova: para que serve o funil. Vender termina em
// Ganhou/Perdeu (com valor); Atender termina em Resolvido/Cancelado. Por baixo
// continua o mesmo `counts_as_sale` de sempre.
export const TIPOS = [
  {
    chave: 'VENDER',
    icone: 'i-lucide-badge-dollar-sign',
    tom: 'bg-n-teal-3 text-n-teal-11',
    venda: true,
  },
  {
    chave: 'ATENDER',
    icone: 'i-lucide-life-buoy',
    tom: 'bg-n-blue-3 text-n-blue-11',
    venda: false,
  },
];
export const tipoDaVenda = venda => (venda ? 'VENDER' : 'ATENDER');

// Categoria de cada etapa, por dentro (sem tela): Novo, Em andamento,
// Esperando o cliente (pausa o prazo) e Resolvido.
export const CATEGORIAS = ['novo', 'andamento', 'espera', 'resolvido'];

// Modelos para começar pronto. Os nomes das etapas são os mesmos que o
// servidor conhece (Crm::Ai::DefaultStageCriteria): o funil já chega com a
// frase de cada etapa. "ideias" completam "Quando usar este funil"; a primeira
// já vem marcada. As etapas de Atender servem a qualquer negócio.
const etapasDo = (chave, total) =>
  Array.from(
    { length: total },
    (_, indice) => `${FUNIL}.MODELOS.${chave}.E${indice + 1}`
  );

// #1802 — `camadas`: o modelo só aparece para a conta com uma dessas camadas do
// pacote (camadasDoPacote); sem o campo, aparece para todas. `sucesso` e
// `falha` trazem o nome dos desfechos (MODELOS.<X>.SUCESSO e .FALHA), que vai
// para metadata.outcome_labels ao criar o funil.
const CORRETORA = ['seguros/corretora'];
const SAUDE = ['seguros/saude_beneficios'];

export const MODELOS = [
  {
    chave: 'VENDAS',
    tipo: 'VENDER',
    icone: 'i-lucide-badge-dollar-sign',
    tom: 'bg-n-teal-3 text-n-teal-11',
    venda: true,
    etapas: etapasDo('VENDAS', 5),
    ideias: ['PRECO', 'COMPRAR', 'COMO_FUNCIONA'],
  },
  {
    chave: 'RENOVACAO',
    tipo: 'VENDER',
    icone: 'i-lucide-refresh-cw',
    tom: 'bg-n-blue-3 text-n-blue-11',
    venda: true,
    camadas: CORRETORA,
    etapas: etapasDo('RENOVACAO', 5),
    // Termina em "Renovou / Não renovou".
    sucesso: true,
    falha: true,
    ideias: ['VAI_VENCER', 'RENOVAR', 'AVISO_RENOVACAO'],
  },
  // Os dois de Atender da corretora vêm antes dos de todos: são o dia a dia
  // dela, e o primeiro do tipo já chega marcado.
  {
    chave: 'SINISTRO',
    tipo: 'ATENDER',
    icone: 'i-lucide-shield-alert',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
    venda: false,
    camadas: CORRETORA,
    etapas: etapasDo('SINISTRO', 4),
    categorias: CATEGORIAS,
    // Traz o nome do sucesso, "Encerrado"; o outro desfecho fica com o nome
    // padrão do Atender.
    sucesso: true,
    ideias: ['BATEU', 'ROUBO', 'ACIONAR'],
  },
  {
    chave: 'ENDOSSO',
    tipo: 'ATENDER',
    icone: 'i-lucide-file-pen-line',
    tom: 'bg-n-violet-3 text-n-violet-11',
    venda: false,
    camadas: CORRETORA,
    etapas: etapasDo('ENDOSSO', 4),
    categorias: CATEGORIAS,
    // Traz o nome do sucesso, "Feito"; o outro desfecho fica com o nome
    // padrão do Atender.
    sucesso: true,
    ideias: ['TROCOU_CARRO', 'MUDOU_ENDERECO', 'INCLUIR_MOTORISTA'],
  },
  // #2083 — a Carteira da saúde: o cliente depois do plano implantado, até o
  // aniversário do contrato. Vem antes dos de todos, como os da corretora.
  // "Aniversário do contrato" não é espera do cliente: a variante da saúde
  // (variantes.json) faz da E3 andamento, e o prazo não pausa.
  {
    chave: 'CARTEIRA',
    tipo: 'ATENDER',
    icone: 'i-lucide-heart-pulse',
    tom: 'bg-n-teal-3 text-n-teal-11',
    venda: false,
    camadas: SAUDE,
    etapas: etapasDo('CARTEIRA', 4),
    categorias: CATEGORIAS,
    // Termina em "Renovado / Cancelado".
    sucesso: true,
    falha: true,
    ideias: ['PLANO_NOVO', 'USAR_PLANO', 'ANIVERSARIO_CONTRATO'],
  },
  {
    chave: 'ATENDIMENTO',
    tipo: 'ATENDER',
    icone: 'i-lucide-life-buoy',
    tom: 'bg-n-blue-3 text-n-blue-11',
    venda: false,
    etapas: etapasDo('ATENDIMENTO', 4),
    categorias: CATEGORIAS,
    ideias: ['AJUDA', 'PROBLEMA', 'COMO_USAR'],
  },
  {
    chave: 'POS_VENDA',
    tipo: 'ATENDER',
    icone: 'i-lucide-package-check',
    tom: 'bg-n-teal-3 text-n-teal-11',
    venda: false,
    etapas: etapasDo('POS_VENDA', 4),
    categorias: CATEGORIAS,
    ideias: ['ACABOU_DE_COMPRAR', 'ENTREGA', 'TROCAR'],
  },
  {
    chave: 'COBRANCA',
    tipo: 'ATENDER',
    icone: 'i-lucide-receipt',
    tom: 'bg-n-amber-3 text-n-amber-11',
    venda: false,
    etapas: etapasDo('COBRANCA', 4),
    categorias: CATEGORIAS,
    // Termina em "Pago / Cancelado".
    sucesso: true,
    ideias: ['PAGAR', 'SEGUNDA_VIA', 'ATRASADO'],
  },
  {
    chave: 'AGENDAMENTOS',
    tipo: 'ATENDER',
    icone: 'i-lucide-calendar-check',
    tom: 'bg-n-violet-3 text-n-violet-11',
    venda: false,
    etapas: etapasDo('AGENDAMENTOS', 4),
    categorias: CATEGORIAS,
    ideias: ['MARCAR', 'REMARCAR', 'HORARIOS'],
  },
];
// #1802 — os modelos de um tipo de conta (os que têm camada: corretora e, desde
// o #2083, saúde). Só o funil que nasceu de um deles usa o nome próprio do
// desfecho no diálogo de "não deu certo" e no aviso depois de marcar; os outros
// funis ficam com o texto de sempre.
export const MODELOS_DE_CAMADA = MODELOS.filter(modelo => modelo.camadas).map(
  modelo => modelo.chave
);
export const usaNomeDoDesfecho = funil =>
  MODELOS_DE_CAMADA.includes(funil?.metadata?.template);

// #1548 (passo 2) — variante do modelo por tipo de conta: a própria lista de
// categorias. Chave = camada do pacote da F1 (#1550); conta sem pacote (ou com
// AUTONOMIA_PACOTES_ENABLED desligado) não tem camada e fica com o modelo de
// hoje. Saúde: no Atendimento, "Esperando a operadora" (E3) não pausa o prazo.
// A lista (variantes.json) é a mesma que o servidor lê em
// Crm::PipelineStages::TemplateVariant.
export const categoriasDoModelo = (modelo, pacote) => {
  const camada = camadasDoPacote(pacote)
    .reverse()
    .find(item => VARIANTES[item]?.[modelo.chave]);
  return camada ? VARIANTES[camada][modelo.chave] : modelo.categorias;
};

// #1802 — os modelos do tipo que a conta vê: os de todas as contas e os da
// camada dela. Conta sem pacote vê a lista de sempre.
const valeNaConta = (modelo, camadas) =>
  !modelo.camadas || modelo.camadas.some(camada => camadas.includes(camada));

export const modelosDoTipo = (tipo, pacote) => {
  const camadas = camadasDoPacote(pacote);
  return MODELOS.filter(
    modelo => modelo.tipo === tipo && valeNaConta(modelo, camadas)
  );
};

// O modelo de um funil salvo (metadata.template), mesmo um da camada; sem ele
// (funis de antes do #1498), o primeiro modelo do tipo que vale para todas.
export const modeloDoFunil = funil => {
  const tipo = tipoDaVenda(funil?.counts_as_sale !== false);
  const salvo = MODELOS.find(
    modelo => modelo.chave === funil?.metadata?.template
  );
  return salvo?.tipo === tipo ? salvo : modelosDoTipo(tipo)[0];
};
export const ehCobranca = funil => modeloDoFunil(funil)?.chave === 'COBRANCA';

// Quanto tempo depois da última mensagem, em palavras de dia a dia:
// "em 4 horas", "amanhã", "em 3 dias", "em 1 semana".
const HORAS_NO_DIA = 24;
const HORAS_NA_SEMANA = 168;
const ATE_HORAS = 12;
const ATE_AMANHA = 36;
export const tempoAte = horas => {
  if (horas < ATE_HORAS) return { chave: 'EM_HORAS', n: horas };
  if (horas < ATE_AMANHA) return { chave: 'AMANHA', n: 1 };
  if (horas % HORAS_NA_SEMANA === 0)
    return { chave: 'EM_SEMANAS', n: horas / HORAS_NA_SEMANA };
  return { chave: 'EM_DIAS', n: Math.round(horas / HORAS_NO_DIA) };
};

// Dias liberados em uma expressão curta: todos os dias, uma faixa seguida
// ("de segunda a sexta") ou a lista. A semana começa na segunda.
const ORDEM_DA_SEMANA = [1, 2, 3, 4, 5, 6, 0];
export const diasEmFaixa = dias => {
  const marcados = ORDEM_DA_SEMANA.filter(dia => dias.includes(dia));
  if (marcados.length === ORDEM_DA_SEMANA.length) return { tipo: 'TODOS' };
  const inicio = ORDEM_DA_SEMANA.indexOf(marcados[0]);
  const seguidos = marcados.every(
    (dia, indice) => ORDEM_DA_SEMANA[inicio + indice] === dia
  );
  if (seguidos && marcados.length > 2)
    return { tipo: 'FAIXA', de: marcados[0], ate: marcados.at(-1) };
  return { tipo: 'LISTA', dias: marcados };
};

// Quando cada retorno sai, se a última mensagem foi numa segunda às 10h:
// soma o tempo sem resposta e empurra para o próximo dia e horário liberados.
const HORA_DO_EXEMPLO = 10;
const SEGUNDA = 1;
export const quandoSai = ({ intervalos, dias, inicio, fim }) =>
  intervalos.map(horas => {
    if (!Number.isFinite(horas) || !dias.length) return null;
    const total = HORA_DO_EXEMPLO + horas;
    let dia = (SEGUNDA + Math.floor(total / 24)) % 7;
    let hora = total % 24;
    let adiante = Math.floor(total / 24);
    if (hora >= fim) {
      dia = (dia + 1) % 7;
      adiante += 1;
      hora = inicio;
    } else if (hora < inicio) hora = inicio;
    let voltas = 0;
    while (!dias.includes(dia) && voltas < 7) {
      dia = (dia + 1) % 7;
      adiante += 1;
      hora = inicio;
      voltas += 1;
    }
    return { dia, hora, semanaQueVem: adiante >= 7 };
  });
