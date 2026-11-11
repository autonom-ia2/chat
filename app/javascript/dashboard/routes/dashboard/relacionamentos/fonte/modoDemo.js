// #2894 — o modo demonstração de Relacionamentos (molde: acharRotas.js).
// `?demo=<estado>` só vale no ambiente de desenvolvimento: no build de produção
// `import.meta.env.DEV` é falso, o parâmetro é ignorado e o estado nunca é
// guardado.
//
// Estados: `cheio`, `vazio`, `carregando` (a fonte nunca responde: esqueleto) e,
// sem `?demo=` válido ou com `?demo=desligado`, a fonte real (hoje: erro).
// #2897 — a carteira soma dois: `sem-seguros` (as pessoas, nenhum seguro) e
// `fora-do-segmento` (as pessoas, conta de outro segmento: nada de seguro
// aparece). Para o bloco A os dois são a conta cheia.
//
// O estado "gruda": depois que uma URL trouxe `?demo=`, as telas seguintes
// continuam em demonstração mesmo sem o parâmetro, porque a navegação interna
// (lista -> ficha -> trazer) não leva a query.
export const DEMO_CARREGANDO = 'carregando';
export const DEMO_SEM_SEGUROS = 'sem-seguros';
export const DEMO_FORA_DO_SEGMENTO = 'fora-do-segmento';
export const ESTADOS_DE_DEMO = [
  'cheio',
  'vazio',
  DEMO_CARREGANDO,
  DEMO_SEM_SEGUROS,
  DEMO_FORA_DO_SEGMENTO,
];
// `?demo=desligado` zera o estado guardado (também só em desenvolvimento).
export const DEMO_DESLIGADO = 'desligado';

const ehEstadoConhecido = valor =>
  typeof valor === 'string' && ESTADOS_DE_DEMO.includes(valor);

export const demoPedido = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.demo;
  return permitida && ehEstadoConhecido(valor) ? valor : null;
};

// Promessa que nunca se resolve: a fonte de exemplo "nunca responde" em
// `?demo=carregando`, e a tela fica no esqueleto para o print.
export const esperarParaSempre = () => new Promise(() => {});

let estadoGuardado = null;

export const estadoDemo = () => estadoGuardado;

// As fontes das três telas perguntam isto: `true` em `?demo=carregando`, quando
// nenhuma resposta deve chegar (use `esperarParaSempre()`).
export const demoCarregando = () => estadoGuardado === DEMO_CARREGANDO;

export const usarDemo = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  if (permitida && query?.demo === DEMO_DESLIGADO) estadoGuardado = null;
  const pedido = demoPedido(query, permitida);
  if (pedido) estadoGuardado = pedido;
  return estadoGuardado;
};
