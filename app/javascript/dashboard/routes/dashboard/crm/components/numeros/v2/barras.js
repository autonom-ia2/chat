// Barras de CRM › Números (#1897) sem estilo em linha: a largura e a marca de
// "hoje" andam em degraus fixos de 5%. As classes ficam escritas por extenso
// para o Tailwind gerá-las. O valor exato continua no texto e no aria da barra.
const LARGURAS = [
  'w-0',
  'w-[5%]',
  'w-[10%]',
  'w-[15%]',
  'w-[20%]',
  'w-[25%]',
  'w-[30%]',
  'w-[35%]',
  'w-[40%]',
  'w-[45%]',
  'w-[50%]',
  'w-[55%]',
  'w-[60%]',
  'w-[65%]',
  'w-[70%]',
  'w-[75%]',
  'w-[80%]',
  'w-[85%]',
  'w-[90%]',
  'w-[95%]',
  'w-full',
];

const INICIOS = [
  'start-0',
  'start-[5%]',
  'start-[10%]',
  'start-[15%]',
  'start-[20%]',
  'start-[25%]',
  'start-[30%]',
  'start-[35%]',
  'start-[40%]',
  'start-[45%]',
  'start-[50%]',
  'start-[55%]',
  'start-[60%]',
  'start-[65%]',
  'start-[70%]',
  'start-[75%]',
  'start-[80%]',
  'start-[85%]',
  'start-[90%]',
  'start-[95%]',
  'start-full',
];

const DEGRAU = 5;
const MAXIMO = 100;

const degrau = pct => {
  const valor = Math.min(MAXIMO, Math.max(0, Number(pct) || 0));
  return Math.round(valor / DEGRAU);
};

export const larguraDe = pct => LARGURAS[degrau(pct)];
export const inicioDe = pct => INICIOS[degrau(pct)];
