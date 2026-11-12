// #2894 — a largura da barra de andamento só com classes do Tailwind (sem
// `style`): uma classe por degrau de 5%, escritas por inteiro para o Tailwind
// enxergá-las. O degrau é o de baixo, e a barra só enche de vez em 100%.
const DEGRAUS = [
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
const PASSO = 5;

export const larguraDaBarra = porcentagem => {
  const limitada = Math.min(100, Math.max(0, Number(porcentagem) || 0));
  return DEGRAUS[Math.floor(limitada / PASSO)];
};
