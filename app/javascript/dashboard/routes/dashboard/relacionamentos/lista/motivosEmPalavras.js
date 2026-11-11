// #2894 — os motivos de quem fica de fora, em palavras, na ordem da regra de
// envio. `prefixo` escolhe o jeito de falar: 'MOTIVO' ("1 está sem telefone",
// dentro de "2 ficam de fora: …") ou 'MOTIVO_CURTO' ("1 sem telefone", na barra
// e no "ninguém aqui pode receber: …").
const MENSAGEM = 'RELACIONAMENTOS.LISTA.MENSAGEM';

export const motivosEmPalavras = (t, conta, prefixo = 'MOTIVO_CURTO') =>
  [
    [conta.naoQuer, 'NAO_QUER'],
    [conta.bloqueados, 'BLOQUEADO'],
    [conta.semTelefone, 'SEM_TELEFONE'],
  ]
    .filter(([quantos]) => quantos > 0)
    .map(([count, chave]) =>
      t(`${MENSAGEM}.${prefixo}_${chave}`, { count }, count)
    );
