import { ref, watch } from 'vue';

// #2775 — F6, as listas da empresa na gaveta: "Está na lista X · Tirar". Tirar
// grava na hora e deixa "Saiu da lista X · Desfazer"; o Desfazer devolve a
// empresa à mesma linha da lista (o servidor só devolve quem foi tirado).
// Lista já enviada não oferece "Tirar" (ela não muda mais). Falha ao ler não
// mostra nada; falha ao tirar ou desfazer mostra a frase de erro.
export function useListasDaEmpresa({ fonte, empresaId, podeLista }) {
  const listas = ref([]);
  const saida = ref(null);
  const ocupado = ref(false);
  const erro = ref(null);

  const carregar = async () => {
    saida.value = null;
    erro.value = null;
    listas.value = [];
    if (!podeLista.value || !empresaId()) return;
    try {
      listas.value = await fonte.value.listasDaEmpresa(empresaId());
    } catch {
      listas.value = [];
    }
  };
  watch([empresaId, podeLista], carregar, { immediate: true });

  const tirar = async lista => {
    ocupado.value = true;
    erro.value = null;
    try {
      const { tirados } = await fonte.value.tirarDaLista({
        listaId: lista.id,
        empresaIds: [empresaId()],
      });
      listas.value = listas.value.filter(item => item.id !== lista.id);
      saida.value = { lista, contatoIds: tirados };
    } catch {
      erro.value = 'TIRAR';
    } finally {
      ocupado.value = false;
    }
  };

  const desfazer = async () => {
    const { lista, contatoIds } = saida.value;
    ocupado.value = true;
    erro.value = null;
    try {
      await fonte.value.devolverNaLista({ listaId: lista.id, contatoIds });
      listas.value = [...listas.value, lista];
      saida.value = null;
    } catch {
      erro.value = 'DESFAZER';
    } finally {
      ocupado.value = false;
    }
  };

  return { listas, saida, ocupado, erro, tirar, desfazer };
}
