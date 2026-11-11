// #2894 — o modo demonstração de Relacionamentos (molde: acharRotas.js).
// `?demo=<estado>` só vale no ambiente de desenvolvimento: no build de produção
// `import.meta.env.DEV` é falso, o parâmetro é ignorado e o estado nunca é
// guardado.
//
// O estado "gruda": depois que uma URL trouxe `?demo=`, as telas seguintes
// continuam em demonstração mesmo sem o parâmetro, porque a navegação interna
// (lista -> ficha -> trazer) não leva a query.
export const ESTADOS_DE_DEMO = ['cheio', 'vazio'];

const ehEstadoConhecido = valor =>
  typeof valor === 'string' && ESTADOS_DE_DEMO.includes(valor);

export const demoPedido = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.demo;
  return permitida && ehEstadoConhecido(valor) ? valor : null;
};

let estadoGuardado = null;

export const estadoDemo = () => estadoGuardado;

export const usarDemo = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const pedido = demoPedido(query, permitida);
  if (pedido) estadoGuardado = pedido;
  return estadoGuardado;
};
