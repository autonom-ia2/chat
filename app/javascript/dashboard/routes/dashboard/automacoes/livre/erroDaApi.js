// #2414 F5 — o que a API do editor respondeu, em frase para a pessoa. 409: outra
// pessoa salvou depois da versão que a tela mostrou (recarregar e mostrar a
// nova). 422: a frase e os problemas da receita, já traduzidos pela API.
export const erroDaApi = (erro, t) => {
  const resposta = erro?.response;
  if (resposta?.status === 409)
    return {
      conflito: true,
      mensagem: t('AUTOMACAO_LIVRE.MUDOU'),
      problemas: [],
    };
  return {
    conflito: false,
    mensagem: resposta?.data?.error || t('AUTOMACAO_LIVRE.FALHOU'),
    problemas: resposta?.data?.problemas || [],
  };
};
