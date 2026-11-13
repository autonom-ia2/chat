import { computed, ref, watch } from 'vue';

// #2499 F6.5 — a gaveta "Editar funil" tem mudança não salva? A etapa pergunta antes de sair
// para o editor da Automação (a gaveta não avisa sozinha e o que foi mudado se perderia). Compara o formulário e as
// frases das etapas com o retrato de quando a gaveta abriu (`sessao` muda a cada abertura). A contagem de cards das
// etapas, que o tempo real atualiza, não conta. As frases chegam depois (painel da IA): o retrato delas sai quando
// ficam prontas.
export const useFunilComMudanca = ({
  form,
  aiPanel,
  frasesProntas,
  sessao,
}) => {
  const retratoDoForm = () =>
    JSON.stringify({
      ...form,
      stages: form.stages.map(etapa => ({
        ...etapa,
        total_cards_count: undefined,
      })),
    });
  const retratoDasFrases = () => {
    const frases = aiPanel.value?.form?.stageCriteria;
    return frases ? JSON.stringify(frases) : null;
  };

  const inicial = ref({ form: '', frases: null });
  const fotografar = () => {
    inicial.value = {
      form: retratoDoForm(),
      frases: frasesProntas.value ? retratoDasFrases() : null,
    };
  };
  watch(sessao, fotografar, { immediate: true });
  watch(frasesProntas, prontas => {
    if (prontas && inicial.value.frases === null)
      inicial.value = { ...inicial.value, frases: retratoDasFrases() };
  });

  return computed(
    () =>
      retratoDoForm() !== inicial.value.form ||
      (inicial.value.frases !== null &&
        retratoDasFrases() !== inicial.value.frases)
  );
};
