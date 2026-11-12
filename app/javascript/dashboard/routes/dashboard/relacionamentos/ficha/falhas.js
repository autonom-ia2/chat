// #2895 — como a ficha fala de erro. A fonte dá nome ao que o servidor recusou
// (fonte/fichaFonte.js) e a tela decide pelo nome, sem olhar código de HTTP:
//   NAO_ACHEI  — a pessoa ou a empresa não existe;
//   SEM_ACESSO — quem está olhando não pode ver aquilo.
// Qualquer outro erro é "não consegui".
export const NAO_ACHEI = 'NAO_ACHEI';
export const SEM_ACESSO = 'SEM_ACESSO';

// Uma parte da ficha (conversas, cards, notas...) que não veio: ou a pessoa não
// pode ver aquela parte (a tela a esconde), ou a leitura falhou (a tela oferece
// tentar de novo). Texto vazio é "veio".
export const FALHA_DA_PARTE = { ERRO: 'erro', SEM_ACESSO: 'semAcesso' };

export const falhaDaParte = falha =>
  falha?.name === SEM_ACESSO ? FALHA_DA_PARTE.SEM_ACESSO : FALHA_DA_PARTE.ERRO;
