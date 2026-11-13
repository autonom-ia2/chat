import { ref } from 'vue';

// #2881, #2976 — a mudança das listas de um agente pronto por ramo (perguntas, documentos, ferramentas), igual na
// criação (useModeloDeRamo) e na página do agente que já atende (RamoNaPagina). A lista na tela é sempre a do
// servidor: cada mudança manda a lista inteira nova e a tela só muda com a resposta.
// `gravar(listas)`: manda `{ [campo]: itens }` ao servidor e devolve a promessa. `pode()`: há o que mudar agora.
// `aoFalhar(erro)`: o servidor recusou ou a rede caiu; quem chama avisa a pessoa.
// `gravando`: { [campo]: true } enquanto a mudança daquela lista está indo.
export function useMudancaDasListas({ gravar, pode, aoFalhar }) {
  const gravando = ref({});
  const marcar = (campo, valor) => {
    gravando.value = { ...gravando.value, [campo]: valor };
  };

  // Um pedido de cada vez no modelo inteiro: cada resposta traz o modelo todo, e duas respostas fora de ordem
  // deixariam na tela uma lista velha (a mudança seguinte nela apagaria a que o dono acabou de fazer). A mudança de
  // outra lista espera a vez.
  let fila = Promise.resolve();
  const naVez = tarefa => {
    const vez = fila.then(tarefa);
    fila = vez.catch(() => {});
    return vez;
  };

  // `campo`: perguntas, documentos ou ferramentas. `itens`: a lista inteira nova.
  const mudar = async (campo, itens) => {
    if (gravando.value[campo] || !pode()) return;
    marcar(campo, true);
    try {
      await naVez(() => gravar({ [campo]: itens }));
    } catch (erro) {
      aoFalhar(erro);
    } finally {
      marcar(campo, false);
    }
  };

  return { gravando, mudar };
}
