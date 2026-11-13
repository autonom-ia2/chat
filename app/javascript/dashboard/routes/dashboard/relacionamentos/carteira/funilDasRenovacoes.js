// #2898 — o funil que a conta escolheu para as renovações parou de servir, e
// as renovações deixaram de virar card:
//   ARQUIVADO: o funil foi arquivado;
//   APAGADO:   o funil, ou a etapa, foi apagado.
// Quem sabe é o servidor. A tela trata os dois como estado de primeira classe:
// o aviso no topo do cartão do funil ("Ajustar renovações"), a frase de quem só
// lê e o convite da aba Seguros.
export const FUNIL_PAROU = { ARQUIVADO: 'ARQUIVADO', APAGADO: 'APAGADO' };

// O ÚNICO ponto que lê, da resposta de `GET seguros/renovacoes`, o sinal de que
// o funil parou de servir. O servidor (#3007) ainda não fechou o nome dos
// campos: até lá nenhum sinal é lido, e a tela se comporta como antes.
// Para ligar: receba a resposta (`resposta => ...`) e devolva
// FUNIL_PAROU.ARQUIVADO, FUNIL_PAROU.APAGADO ou '' (o funil serve). Nada mais
// na tela precisa mudar; os testes de cada estado trocam só esta função.
export const funilParou = () => '';
