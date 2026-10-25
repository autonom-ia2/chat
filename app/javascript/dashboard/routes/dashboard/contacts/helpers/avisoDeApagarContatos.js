// #2138: o aviso da exclusão em massa diz que as conversas e mensagens saem junto. Um contato selecionado usa o mesmo
// texto da página do contato; dois ou mais, o plural com a quantidade.
export const avisoDeApagarContatos = (t, quantidade) =>
  quantidade > 1
    ? t('APAGAR_CONTATO.VARIOS', { count: quantidade })
    : t('APAGAR_CONTATO.UM');
