import { computed, ref } from 'vue';

// #2894 — as pessoas marcadas na lista. Guarda a pessoa inteira (não só o id)
// porque os diálogos de ação em grupo precisam saber quem tem telefone e quem
// não quer mensagens. O mapa nunca é alterado no lugar: cada mudança troca por
// um novo, e o Vue percebe.
export const useMarcados = () => {
  const mapa = ref(new Map());

  const quantos = computed(() => mapa.value.size);
  const pessoas = computed(() => [...mapa.value.values()]);
  const ehMarcado = id => mapa.value.has(id);

  const alternar = pessoa => {
    const proximo = new Map(mapa.value);
    if (proximo.has(pessoa.id)) proximo.delete(pessoa.id);
    else proximo.set(pessoa.id, pessoa);
    mapa.value = proximo;
  };

  const marcarVarias = lista => {
    mapa.value = new Map(lista.map(pessoa => [pessoa.id, pessoa]));
  };

  const limpar = () => {
    if (mapa.value.size) mapa.value = new Map();
  };

  return { quantos, pessoas, ehMarcado, alternar, marcarVarias, limpar };
};
