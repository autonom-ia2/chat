// #2202 (PR 3) — o que a pessoa tocou na escolha de etiquetas e ainda não voltou
// do servidor. Fica no módulo, um só para as duas janelas (o ⋯ do topo e o bloco
// do painel): as duas mostram as mesmas marcas.
//
// Cada toque vira uma intenção — pôr ou tirar UMA etiqueta — presa à conversa
// em que a pessoa tocou, e vai ao servidor assim (labels/alterar). O servidor
// aplica sobre o que a conversa tem na hora, dentro de um lock; por isso nenhuma
// janela, aba ou pessoa apaga a etiqueta da outra. A resposta (a lista final)
// entra no store pela action de sempre. A fila por conversa só mantém a ordem
// dos toques (pôr e logo tirar a mesma etiqueta).
import { shallowRef } from 'vue';
import { useStore } from 'dashboard/composables/store';
import ConversationAPI from 'dashboard/api/conversations';
import EtiquetasDaConversaAPI from 'dashboard/api/etiquetasDaConversa';

const pendentes = shallowRef([]);
const filas = new Map();
let ultimaIntencao = 0;

const aplicar = (titulos, { acao, titulo }) => {
  if (acao === 'tirar') return titulos.filter(item => item !== titulo);
  return titulos.includes(titulo) ? titulos : [...titulos, titulo];
};

// Só para os specs: o estado é do módulo e passaria de um teste para outro.
export const esquecerTudo = () => {
  pendentes.value = [];
  filas.clear();
};

export function useEtiquetasDaConversa() {
  const store = useStore();

  // A conversa já tem registro de etiquetas no store? Sem ele, a lista viria
  // vazia e a tela mostraria como tiradas etiquetas que a conversa tem.
  const temRegistro = id =>
    store.state.conversationLabels?.records?.[Number(id)] !== undefined;
  // true quando o registro chegou; false quando a busca falhou. Não usa a action
  // conversationLabels/get: ela engole o erro, e a janela ficaria carregando
  // para sempre. A resposta entra no store pela mesma mutation.
  const carregar = async id => {
    try {
      const { data } = await ConversationAPI.getLabels(id);
      await store.dispatch('conversationLabels/setConversationLabel', {
        id,
        data: data.payload,
      });
      return true;
    } catch {
      return false;
    }
  };

  // O que está gravado, com as intenções desta conversa que ainda não voltaram
  // por cima (a marca aparece na hora do toque).
  const marcadasEm = (conversaId, gravadas) =>
    pendentes.value
      .filter(intencao => intencao.conversaId === conversaId)
      .reduce(aplicar, gravadas);

  // true quando o servidor gravou; false quando ESTA chamada falhou.
  const gravar = async ({ conversaId, acao, titulo }) => {
    try {
      const { data } = await EtiquetasDaConversaAPI.alterar(conversaId, {
        [acao]: [titulo],
      });
      await store.dispatch('conversationLabels/setConversationLabel', {
        id: conversaId,
        data: data.payload,
      });
      return true;
    } catch {
      return false;
    }
  };

  const tocar = (conversaId, acao, titulo) => {
    ultimaIntencao += 1;
    const intencao = { id: ultimaIntencao, conversaId, acao, titulo };
    pendentes.value = [...pendentes.value, intencao];
    const anterior = filas.get(conversaId) || Promise.resolve();
    const resultado = anterior
      .then(() => gravar(intencao))
      .then(gravou => {
        // Respondeu (ou falhou): na tela passa a valer o que está gravado.
        pendentes.value = pendentes.value.filter(
          item => item.id !== intencao.id
        );
        if (filas.get(conversaId) === resultado) filas.delete(conversaId);
        return gravou;
      });
    filas.set(conversaId, resultado);
    return resultado;
  };

  return { temRegistro, carregar, marcadasEm, tocar };
}
