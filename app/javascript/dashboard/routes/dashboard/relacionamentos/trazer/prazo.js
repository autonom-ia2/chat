// #2894 — as situações de uma lista trazida. Lista pronta tem Desfazer sempre,
// sem data limite; trazendo ainda não dá para desfazer; desfeita já foi.
// #2896 — `desfazendo`: a pessoa pediu para desfazer e o servidor ainda está
// tirando o que a lista pôs. A tela acompanha até virar `desfeito`.
// #2896 — `falhou`: a lista parou no meio. Quando o servidor diz que dá para
// continuar (`podeTentar`), o histórico oferece "Tentar de novo".
export const SITUACOES_DA_LISTA = {
  PRONTO: 'pronto',
  TRAZENDO: 'trazendo',
  DESFAZENDO: 'desfazendo',
  DESFEITO: 'desfeito',
  FALHOU: 'falhou',
};

// O dia em palavras da casa ("08/11"), para dizer quando a lista foi trazida.
export const formatarDia = (ms, locale = 'pt-BR') =>
  new Intl.DateTimeFormat(String(locale).replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
  }).format(new Date(ms));
