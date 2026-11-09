// #2692 — nomes próprios das rotas da Prospecção nova (sem reaproveitar os de
// hoje, que continuam com a flag desligada).
export const ROTAS = {
  PORTA: 'autonomia_prospecting_achar',
  BUSCAS: 'autonomia_prospecting_achar_buscas',
  BUSCA: 'autonomia_prospecting_achar_busca',
  // A mesma lista, aberta logo depois de buscar: o menu marca "Achar empresas"
  // e não "Buscas" (D8 da crítica r5).
  NOVA: 'autonomia_prospecting_achar_nova',
  FILA: 'autonomia_prospecting_para_chamar',
  // A aba "Suas listas" de "Suas buscas" e uma lista aberta (#2775, F6).
  LISTAS: 'autonomia_prospecting_achar_listas',
  LISTA: 'autonomia_prospecting_achar_lista',
};

// O estado da demonstração pedido no endereço (?demo=<estado>), só no ambiente
// de desenvolvimento: no build de produção `import.meta.env.DEV` é falso.
export const demoPedido = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.demo;
  return permitida && typeof valor === 'string' && valor ? valor : null;
};
