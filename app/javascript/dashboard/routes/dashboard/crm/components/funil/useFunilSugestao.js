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
    const request = {
      stages: snapshot,
      stage_index: form.stages.indexOf(target),
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
