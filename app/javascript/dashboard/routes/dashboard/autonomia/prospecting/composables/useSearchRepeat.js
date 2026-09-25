// Repetir e editar uma busca do histórico (#678). As duas enchem o formulário
// com tudo o que a busca salva pediu (cada frente restaura o próprio pedaço em
// searchSlices/, restoreForm) e o destino no CRM dela. "Editar" para aí;
// "Repetir" envia na hora. Se o envio falha, o formulário fica aberto e
// preenchido, com o erro, como numa busca nova.
import { resetSlices, restoreFormSlices } from './searchSlices';

export const useSearchRepeat = (state, { applyCrmTarget, submitSearch }) => {
  const { form, defaultSearchForm, showNewSearch, selectedLeadDetailId } =
    state;

  const fillFormFrom = async search => {
    selectedLeadDetailId.value = null;
    form.value = defaultSearchForm();
    resetSlices(state);
    restoreFormSlices(state, search);
    await applyCrmTarget(search);
    showNewSearch.value = true;
  };

  const editSearch = async search => {
    await fillFormFrom(search);
  };

  const repeatSearch = async search => {
    await fillFormFrom(search);
    await submitSearch({ fresh: true });
  };

  return { editSearch, repeatSearch };
};
