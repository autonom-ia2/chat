import { reactive } from 'vue';

// G52 (#2760) — o passo "Pôr na lista de e-mail". A receita guarda só o id da
// lista; o nome, para a frase do passo, vem das listas que o editor carregou
// (useOpcoesDaConta). Sem o nome ainda, a frase é a do passo.
const nomes = reactive({});

export const guardarNomesDasListas = listas => {
  (listas || []).forEach(lista => {
    nomes[lista.id] = lista.name;
  });
};

export const nomeDaLista = id => nomes[id];

export const fraseDaListaDeEmail = (passo, t) => {
  const nome = nomeDaLista(passo.lista_id);
  return nome
    ? t('AUTOMACAO_LIVRE.LISTA_DE_EMAIL.FRASE', { nome })
    : t('AUTOMACAO_LIVRE.PASSOS.LISTA_DE_EMAIL');
};
