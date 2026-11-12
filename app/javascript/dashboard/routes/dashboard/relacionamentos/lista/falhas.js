// #2894 — as falhas da lista que têm nome. `SEM_ACESSO`: o servidor disse que a
// pessoa não pode ver (401 ou 403). Tentar de novo não resolve, então a tela
// diz isso em vez de oferecer o botão.
export const SEM_ACESSO = 'SEM_ACESSO';

export const ehSemAcesso = falha => falha?.name === SEM_ACESSO;
