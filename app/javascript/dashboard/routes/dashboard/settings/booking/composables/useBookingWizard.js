import { computed, ref } from 'vue';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { STEP } from '../constants';
import {
  formToPayload,
  imageProblem,
  pageToForm,
  serverProblem,
  stepProblem,
} from '../bookingPageForm';
import { joinNames } from '../bookingFormat';

const SAVE_ERROR = 'BOOKING.WIZARD.SAVE_ERROR';
const VALID_STEPS = Object.values(STEP);

// O aviso de uma chamada que falhou: o próprio da recusa ou o geral.
const saveErrorFrom = failure => {
  const problem = serverProblem(failure?.response?.data);
  return problem ? `BOOKING.WIZARD.SERVER_ERRORS.${problem}` : SAVE_ERROR;
};

// Estado e chamadas do assistente de seis passos (J3). Um formulário só para a
// página inteira: voltar um passo não perde o que foi digitado. Cada
// "Continuar" confere o passo e salva (PATCH); o último passo publica.
// `initialStep` abre uma página existente direto num passo (ex.: a prévia).
export const useBookingWizard = ({ pageId, initialStep, onClose }) => {
  const openingStep = VALID_STEPS.includes(initialStep)
    ? initialStep
    : STEP.CONTE;
  const step = ref(pageId ? openingStep : STEP.MODELO);
  const page = ref(null);
  const form = ref(null);
  const loading = ref(Boolean(pageId));
  const loadFailed = ref(false);
  // A página já estava no ar quando foi aberta: o que mudar vale na hora.
  const liveOnOpen = ref(false);
  const people = ref([]);
  const peopleState = ref('loading');
  const busy = ref(false);
  const error = ref('');
  // Chave i18n do aviso de "não salvou" ('' = sem aviso).
  const saveError = ref('');
  const uploading = ref(null);
  const uploadError = ref(null);
  const missing = ref([]);
  const savingDestination = ref(false);

  const loadPeople = async () => {
    peopleState.value = 'loading';
    try {
      const { data } = await BookingPagesAPI.people(page.value.id);
      people.value = data.payload || [];
      peopleState.value = 'ready';
    } catch {
      peopleState.value = 'error';
    }
  };

  const open = payload => {
    page.value = payload;
    form.value = pageToForm(payload);
    loadPeople();
  };

  const load = async () => {
    if (!pageId) return;
    try {
      const { data } = await BookingPagesAPI.show(pageId);
      liveOnOpen.value = data.payload?.enabled === true;
      open(data.payload);
    } catch {
      loadFailed.value = true;
    } finally {
      loading.value = false;
    }
  };

  const change = patch => {
    form.value = { ...form.value, ...patch };
    error.value = '';
  };

  // Roda uma chamada com o botão ocupado; falha vira o aviso de "não salvou",
  // com o motivo quando o servidor diz qual é.
  const attempt = async (action, flag = busy) => {
    flag.value = true;
    saveError.value = '';
    try {
      await action();
    } catch (failure) {
      saveError.value = saveErrorFrom(failure);
    } finally {
      flag.value = false;
    }
  };

  const chooseTemplate = templateKey =>
    attempt(async () => {
      const { data } = await BookingPagesAPI.create({ templateKey });
      open(data.payload);
      step.value = STEP.CONTE;
    });

  const samePeople = () => {
    const saved = (page.value.people || []).map(person => person.id).sort();
    const chosen = [...form.value.peopleIds].sort();
    return saved.join(',') === chosen.join(',');
  };

  const saveStep = async () => {
    const { data } = await BookingPagesAPI.update(
      page.value.id,
      formToPayload(form.value)
    );
    page.value = data.payload;
    if (step.value !== STEP.CONTE || samePeople()) return;
    const response = await BookingPagesAPI.updatePeople(
      page.value.id,
      form.value.peopleIds
    );
    page.value = response.data.payload;
  };

  const next = () => {
    const problem = stepProblem(step.value, form.value);
    if (problem) {
      error.value = problem;
      return Promise.resolve();
    }
    return attempt(async () => {
      await saveStep();
      step.value += 1;
    });
  };

  const back = () => {
    error.value = '';
    saveError.value = '';
    if (step.value <= STEP.CONTE) {
      onClose();
      return;
    }
    step.value -= 1;
  };

  // Só passos que existem: uma pendência desconhecida não tira a pessoa da tela.
  const goTo = target => {
    if (!VALID_STEPS.includes(target)) return;
    missing.value = [];
    step.value = target;
  };

  const publish = async () => {
    busy.value = true;
    saveError.value = '';
    missing.value = [];
    try {
      const { data } = await BookingPagesAPI.publish(page.value.id);
      page.value = data.payload;
    } catch (failure) {
      const list = failure?.response?.data?.missing;
      if (list?.length) missing.value = list;
      else saveError.value = saveErrorFrom(failure);
    } finally {
      busy.value = false;
    }
  };

  const upload = async ({ kind, file }) => {
    const problem = imageProblem(file);
    uploadError.value = problem ? { kind, key: problem } : null;
    if (problem) return;
    uploading.value = kind;
    try {
      const { data } = await BookingPagesAPI.uploadImage(
        page.value.id,
        kind,
        file
      );
      page.value = data.payload;
    } catch {
      uploadError.value = { kind, key: 'IMAGE_UPLOAD' };
    } finally {
      uploading.value = null;
    }
  };

  const saveDestination = ({ pipelineId, stageId }) =>
    attempt(async () => {
      const { data } = await BookingPagesAPI.update(page.value.id, {
        default_pipeline_id: pipelineId,
        default_stage_id: stageId,
      });
      page.value = data.payload;
      change({ pipelineId, stageId });
      missing.value = missing.value.filter(item => item !== 'pipeline');
    }, savingDestination);

  const peopleNames = computed(() => {
    if (!form.value) return '';
    const known = [...people.value, ...(page.value?.people || [])];
    return joinNames(
      form.value.peopleIds.map(
        id => known.find(person => person.id === id)?.name
      )
    );
  });

  return {
    step,
    page,
    form,
    loading,
    loadFailed,
    liveOnOpen,
    people,
    peopleState,
    busy,
    error,
    saveError,
    uploading,
    uploadError,
    missing,
    savingDestination,
    peopleNames,
    load,
    loadPeople,
    change,
    chooseTemplate,
    next,
    back,
    goTo,
    publish,
    upload,
    saveDestination,
  };
};
