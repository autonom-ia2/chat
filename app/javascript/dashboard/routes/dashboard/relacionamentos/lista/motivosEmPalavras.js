// #2894 — os motivos de quem fica de fora, em palavras, na ordem da regra de
// envio. Uma regra de texto só (neutra de gênero) para a barra e o diálogo:
// "1 pediu para não receber", "1 com bloqueio", "1 sem telefone".
const MENSAGEM = 'RELACIONAMENTOS.LISTA.MENSAGEM';

export const motivosEmPalavras = (t, conta) =>
  [
    [conta.naoQuer, 'NAO_QUER'],
    [conta.bloqueados, 'BLOQUEADO'],
    [conta.semTelefone, 'SEM_TELEFONE'],
  ]
    .filter(([quantos]) => quantos > 0)
    .map(([count, chave]) =>
      t(`${MENSAGEM}.MOTIVO_${chave}`, { count }, count)
    );
