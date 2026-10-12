// #1384 — o que a gaveta de funil usa em mais de um lugar: modelos prontos,
// cores das etapas, o resumo dos retornos e o calendário das tentativas.

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

export const seloDaCor = cor =>
  CORES.find(item => item.valor === cor)?.selo || 'bg-n-blue-3 text-n-blue-11';

// Modelos para começar pronto. Os nomes das etapas de Vendas são os mesmos
// que o servidor conhece (Crm::Ai::DefaultStageCriteria): o funil já chega
// com a frase de cada etapa. "quandoUsar" é a ideia que já vem marcada em
// "Quando usar este funil".
const etapasDo = (chave, total) =>
  Array.from(
    { length: total },
    (_, indice) => `${FUNIL}.MODELOS.${chave}.E${indice + 1}`
  );

export const MODELOS = [
  {
    chave: 'VENDAS',
    icone: 'i-lucide-badge-dollar-sign',
    tom: 'bg-n-teal-3 text-n-teal-11',
    venda: true,
    etapas: etapasDo('VENDAS', 5),
    ideias: ['PRECO', 'COMPRAR', 'COMO_FUNCIONA'],
  },
  {
    chave: 'ATENDIMENTO',
    icone: 'i-lucide-life-buoy',
    tom: 'bg-n-blue-3 text-n-blue-11',
    venda: false,
    etapas: etapasDo('ATENDIMENTO', 4),
    ideias: ['AJUDA', 'PROBLEMA', 'TROCAR'],
  },
  {
    chave: 'AGENDAMENTOS',
    icone: 'i-lucide-calendar-check',
    tom: 'bg-n-violet-3 text-n-violet-11',
    venda: true,
    etapas: etapasDo('AGENDAMENTOS', 4),
    ideias: ['MARCAR', 'REMARCAR', 'HORARIOS'],
  },
];

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
