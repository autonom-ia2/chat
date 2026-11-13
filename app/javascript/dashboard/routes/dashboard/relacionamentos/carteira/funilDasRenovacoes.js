// #2898 — o funil que a conta escolheu para as renovações parou de servir, e
// as renovações deixaram de virar card:
//   ARQUIVADO: o funil foi arquivado;
//   APAGADO:   o funil, ou a etapa, foi apagado.
// Quem sabe é o servidor. A tela trata os dois como estado de primeira classe:
// o aviso no topo do cartão do funil ("Ajustar renovações"), a frase de quem só
// lê e o convite da aba Seguros.
export const FUNIL_PAROU = { ARQUIVADO: 'ARQUIVADO', APAGADO: 'APAGADO' };

// Como está a escolha do funil, nas palavras do servidor (`escolha` da resposta
// de `GET seguros/renovacoes`, Carteira::RenovacaoConfig#escolha): `feita`,
// `nunca_feita`, `funil_arquivado` ou `sumiu`. Só as duas últimas dizem que o
// funil parou.
const DA_ESCOLHA = new Map([
  ['funil_arquivado', FUNIL_PAROU.ARQUIVADO],
  ['sumiu', FUNIL_PAROU.APAGADO],
]);

// O ÚNICO ponto que lê, da resposta de `GET seguros/renovacoes`, o sinal de que
// o funil parou de servir. Devolve FUNIL_PAROU.ARQUIVADO, FUNIL_PAROU.APAGADO
// ou '' (o funil serve, ou a conta nunca escolheu). A escolha que a tela ainda
// não conhece não vira aviso.
export const funilParou = resposta => DA_ESCOLHA.get(resposta?.escolha) ?? '';
