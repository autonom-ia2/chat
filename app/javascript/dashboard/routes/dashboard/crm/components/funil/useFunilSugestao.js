import { ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #1384 — "Deixar mais claro" e "Sugerir uma frase": pede a frase de uma
// etapa ao servidor e guarda a sugestão até a pessoa escolher. Se a conversa
// mudou enquanto esperava (outra etapa, outra frase, gaveta fechada), a
// resposta não é usada.
export const useFunilSugestao = ({
  form,
  criteriaFor,
  selectedStage,
  selectedCriteria,
  editorSession,
  editando,
  pipelineId,
  aberta,
}) => {
  const improving = ref(false);
  const suggestion = ref(null);
  const improvementError = ref(false);

  const frasesAtuais = () =>
    form.stages.map(stage => ({
      // #1920: o servidor acha a etapa salva pelo id (nunca pela posição);
      // etapa nova ainda não tem.
      ...(stage.id ? { id: stage.id } : {}),
      name: stage.name,
      description: criteriaFor(stage),
    }));
  const improveCriteria = async () => {
    const target = selectedStage.value;
    const session = editorSession.value;
    const snapshot = frasesAtuais();
    improving.value = true;
    suggestion.value = null;
    improvementError.value = false;
    // #1920: o tipo e o "quando usar" do formulário (mesmo sem salvar) dão a
    // fronteira certa à IA que escreve a frase.
    const request = {
      stages: snapshot,
      stage_index: form.stages.indexOf(target),
      funil: {
        counts_as_sale: form.countsAsSale,
        when_to_use: form.whenToUse.trim(),
      },
    };
    try {
      // #1384: funil ainda não salvo também pede a sugestão, pela rota da conta.
      const { data } = editando.value
        ? await CrmKanbanAPI.improveStageCriteria(pipelineId.value, request)
        : await CrmKanbanAPI.improveDraftStageCriteria({
            ...request,
            pipeline_name: form.name.trim(),
          });
      if (
        session !== editorSession.value ||
        selectedStage.value !== target ||
        !aberta.value
      )
        return;
      if (JSON.stringify(snapshot) !== JSON.stringify(frasesAtuais())) {
        improvementError.value = true;
        return;
      }
      suggestion.value = data;
    } catch {
      if (session === editorSession.value) improvementError.value = true;
    } finally {
      if (session === editorSession.value) improving.value = false;
    }
  };
  const applySuggestion = () => {
    selectedCriteria.value = suggestion.value.description;
    suggestion.value = null;
  };

  return {
    improving,
    suggestion,
    improvementError,
    improveCriteria,
    applySuggestion,
  };
};
