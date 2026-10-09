import { computed, inject, nextTick, provide, ref } from 'vue';
import { createBooking, getPage, requestContact } from '../api';
import { applyBrandColor } from '../helpers/brand';
import {
  bookingDays,
  clientTimeZone,
  dateInZone,
  isValidTimeZone,
  sameClock,
} from '../helpers/datetime';
import { newRequestId } from '../helpers/requestId';
import { useBookingForm } from './useBookingForm';
import { useFormToken } from './useFormToken';
import { useInvite } from './useInvite';
import { useManage } from './useManage';
import { useSlots } from './useSlots';
import { useStepHistory } from './useStepHistory';

export const STEPS = Object.freeze({
  LOADING: 'loading',
  NOT_FOUND: 'not_found',
  ERROR: 'error',
  PAUSED: 'paused',
  MANAGE: 'manage',
  MANAGE_CANCEL: 'manage_cancel',
  MANAGE_STOP: 'manage_stop',
  RESCHEDULE: 'reschedule',
  DATE: 'date',
  TIME: 'time',
  DETAILS: 'details',
  CONFIRM: 'confirm',
  DONE: 'done',
  NO_SLOT: 'no_slot',
});

// Telas de escolher dia e hora (marcar ou remarcar): entre elas o "voltar" do celular refaz a tela anterior.
const BOOKING_STEPS = [
  STEPS.DATE,
  STEPS.TIME,
  STEPS.DETAILS,
  STEPS.CONFIRM,
  STEPS.NO_SLOT,
  STEPS.RESCHEDULE,
];

const FLOW_KEY = Symbol('bookingFlow');

// `/book/:slug` (link público ou de pessoa) e `/b/:code` (link do cliente). `?preview=` só no link de página;
// `?stop_notices=1` só no link do cliente (o "Parar avisos" das mensagens automáticas).
export const parseRoute = (pathname, search) => {
  const parts = String(pathname || '')
    .split('/')
    .filter(Boolean);
  const params = new URLSearchParams(search || '');
  const preview = params.get('preview') || null;
  if (parts[0] === 'b' && parts[1]) {
    return {
      code: parts[1],
      slug: null,
      stopNotices: params.get('stop_notices') === '1',
    };
  }
  if (parts[0] === 'book' && parts[1]) {
    return { code: null, slug: parts[1], preview };
  }
  return { code: null, slug: null };
};

// Primeiro campo marcado como inválido recebe o foco: o leitor de tela lê o rótulo e o erro dele.
const focusFirstInvalid = () =>
  nextTick(() => document.querySelector('[aria-invalid="true"]')?.focus());

export function useBookingFlow(location = window.location) {
  const route = parseRoute(location.pathname, location.search);
  const step = ref(STEPS.LOADING);
  const page = ref(null);
  const slug = ref(route.slug);
  const duration = ref(null);
  const locationType = ref(null);
  const selectedDate = ref('');
  const selectedSlot = ref('');
  const slotNotice = ref('');
  const isChangingPhone = ref(false);
  const isNameRequested = ref(false);
  const isSubmitting = ref(false);
  const result = ref(null);
  const isContactRequested = ref(false);
  const clientZone = clientTimeZone();
  // Chave da tentativa de reserva: a mesma no reenvio depois de falha de rede ou do servidor (a reserva pode ter
  // sido feita); nova depois de uma resposta definitiva ou de outro horário.
  let requestId = null;

  const invite = useInvite();
  const slotsApi = useSlots({ slug, duration });
  const bookingForm = useBookingForm();
  const { form } = bookingForm;
  const formToken = useFormToken({ page, slug, preview: route.preview });

  const timeZone = computed(() => page.value?.timezone || '');
  const isPreview = computed(() => !!page.value?.preview);
  // O relógio de quem abre marca outra hora que o da página: as telas dizem em que horário estão as horas.
  const isOtherClock = computed(
    () => !!timeZone.value && !sameClock(clientZone, timeZone.value)
  );
  const days = computed(() =>
    page.value
      ? bookingDays(
          timeZone.value,
          page.value.booking_window_days,
          page.value.weekdays
        )
      : []
  );
  const durations = computed(() =>
    Array.isArray(page.value?.durations) ? page.value.durations : []
  );
  const locations = computed(() =>
    Array.isArray(page.value?.locations) ? page.value.locations : []
  );
  const selectedLocation = computed(
    () =>
      locations.value.find(item => item.type === locationType.value) ||
      locations.value[0] ||
      null
  );
  const emailRequired = computed(
    () => !!selectedLocation.value?.requires_email
  );
  // No convite o nome e o número vêm do contato; o campo só aparece se faltar, se a pessoa pedir para mudar o número
  // ou se o servidor recusar (e fica aberto depois disso, sem piscar a cada envio).
  const askName = computed(
    () =>
      !invite.isInvite.value || !invite.firstName.value || isNameRequested.value
  );
  const askPhone = computed(
    () =>
      !invite.isInvite.value ||
      !invite.phoneMasked.value ||
      isChangingPhone.value
  );
  const greetingName = computed(
    () => invite.firstName.value || form.name.trim().split(' ')[0] || ''
  );
  const captchaRequired = computed(() => !!page.value?.captcha_site_key);

  const goTo = next => {
    bookingForm.clearErrors();
    step.value = next;
  };

  const showTimes = date => {
    selectedDate.value = date;
    selectedSlot.value = '';
    slotNotice.value = '';
    goTo(STEPS.TIME);
    slotsApi.loadSlots(date);
  };

  const history = useStepHistory();

  // Tela nova por escolha da pessoa: entra no histórico (a mesma tela de novo só substitui).
  const navigate = next => {
    if (step.value === next) history.replace(next);
    else history.push(next);
  };

  const finishOn = next => {
    goTo(next);
    history.start(next);
  };

  const startBooking = () => {
    finishOn(STEPS.DATE);
    slotsApi.loadNextSlot();
  };

  const backToTimes = () => {
    history.replace(STEPS.TIME);
    showTimes(selectedDate.value);
    slotNotice.value = 'BOOKING_V2.ERRORS.SLOT_UNAVAILABLE';
    slotsApi.loadNextSlot();
  };

  // Duração, local e nome do convite para uma reserva nova (a primeira, ou outra depois de cancelada).
  const prepareBooking = () => {
    duration.value = page.value.duration_minutes;
    locationType.value = locations.value[0]?.type || null;
    if (invite.firstName.value) form.name = invite.firstName.value;
    requestId = null;
  };

  const manage = useManage({
    steps: STEPS,
    step,
    page,
    invite,
    history,
    goTo,
    finishOn,
    duration,
    durations,
    selectedDate,
    selectedSlot,
    slots: slotsApi,
    backToTimes,
    prepareBooking,
    stopRequested: !!route.stopNotices,
  });

  const detailsStep = () => {
    if (manage.isRescheduling.value) return STEPS.RESCHEDULE;
    return invite.isInvite.value ? STEPS.CONFIRM : STEPS.DETAILS;
  };

  // Volta pelo histórico: refaz a tela pedida com o que já foi escolhido; sem o dado, cai no dia. Reserva feita e
  // ação concluída na tela da reunião não se desfazem com o voltar; das outras telas da gestão, volta para ela.
  const restoreStep = target => {
    if (step.value === STEPS.MANAGE) return null;
    if (invite.isScheduled.value && !BOOKING_STEPS.includes(target)) {
      return manage.show();
    }
    if (!BOOKING_STEPS.includes(step.value)) return null;
    if (target === STEPS.TIME && selectedDate.value) {
      return showTimes(selectedDate.value);
    }
    if (target === detailsStep() && selectedSlot.value) return goTo(target);
    if (target === STEPS.NO_SLOT) return goTo(STEPS.NO_SLOT);
    return goTo(STEPS.DATE);
  };

  history.restoreWith(restoreStep);

  // Convite agendado abre a reunião mesmo com a página pausada: o cliente ainda precisa poder cancelar.
  const showPage = data => {
    page.value = data;
    formToken.markIssued();
    applyBrandColor(data?.brand?.color);
    if (invite.isScheduled.value) return manage.open();
    if (data?.paused) return finishOn(STEPS.PAUSED);
    if (!isValidTimeZone(data?.timezone)) return finishOn(STEPS.ERROR);

    prepareBooking();
    return startBooking();
  };

  // Convite agendado abre a reunião mesmo quando a página não abre mais (responsável que saiu, página apagada): o
  // cliente ainda vê o horário e pode cancelar; sem os dados da página, como página pausada.
  const loadPage = async () => {
    try {
      return await getPage(slug.value, route.preview);
    } catch (error) {
      if (error?.status !== 404 || !invite.isScheduled.value) throw error;
      return { slug: slug.value, paused: true };
    }
  };

  const load = async () => {
    step.value = STEPS.LOADING;
    try {
      if (route.code) {
        const data = await invite.load(route.code);
        slug.value = data?.page_slug || null;
      }
      if (!slug.value) return finishOn(STEPS.NOT_FOUND);
      return showPage(await loadPage());
    } catch (error) {
      return finishOn(error?.status === 404 ? STEPS.NOT_FOUND : STEPS.ERROR);
    }
  };

  const chooseDuration = minutes => {
    duration.value = minutes;
    slotsApi.loadNextSlot();
  };

  const chooseDay = date => {
    navigate(STEPS.TIME);
    showTimes(date);
  };

  const chooseSlot = iso => {
    requestId = null;
    selectedSlot.value = iso;
    slotNotice.value = '';
    navigate(detailsStep());
    goTo(detailsStep());
  };

  const chooseEarliest = () => {
    const iso = slotsApi.nextSlot.value;
    if (!iso) return;
    selectedDate.value = dateInZone(new Date(iso), timeZone.value);
    chooseSlot(iso);
  };

  // "Voltar" da página: pelo histórico quando há (o mesmo caminho do voltar do celular); senão direto.
  const goBack = () => {
    if (history.back()) return null;
    if (step.value === detailsStep()) {
      history.replace(STEPS.TIME);
      return showTimes(selectedDate.value);
    }
    history.replace(STEPS.DATE);
    return goTo(STEPS.DATE);
  };

  const openNoSlot = () => {
    navigate(STEPS.NO_SLOT);
    goTo(STEPS.NO_SLOT);
  };

  const startPhoneChange = () => {
    isChangingPhone.value = true;
  };

  const bookingPayload = () => ({
    name: form.name.trim(),
    phone: askPhone.value ? bookingForm.phoneValue() : undefined,
    email: form.email.trim() || undefined,
    starts_at: selectedSlot.value,
    duration: duration.value,
    location_type: selectedLocation.value?.type,
    invite_code: invite.invite.value?.code,
    consent: bookingForm.consent(!!page.value.notices_enabled),
    company: form.company,
    form_token: page.value.form_token,
    captcha_token: bookingForm.captchaToken.value || undefined,
    request_id: requestId,
  });

  const isRetriable = error => !error?.status || error.status >= 500;

  // Erro de campo abre o campo (no convite ele pode estar escondido) e leva o foco até ele.
  const showServerError = code => {
    const field = bookingForm.applyServerError(code);
    if (field === 'phone') isChangingPhone.value = true;
    if (field === 'name') isNameRequested.value = true;
    if (field) focusFirstInvalid();
  };

  const isFormValid = options => {
    const isValid = bookingForm.validate({
      captchaRequired: captchaRequired.value,
      ...options,
    });
    if (!isValid) focusFirstInvalid();
    return isValid;
  };

  const submitBooking = async () => {
    if (isSubmitting.value || isPreview.value) return;
    const isValid = isFormValid({
      askName: askName.value,
      askPhone: askPhone.value,
      emailRequired: emailRequired.value,
    });
    if (!isValid) return;

    isSubmitting.value = true;
    requestId = requestId || newRequestId();
    try {
      result.value = await formToken.sendWithFreshToken(() =>
        createBooking(slug.value, bookingPayload())
      );
      requestId = null;
      goTo(STEPS.DONE);
      history.replace(STEPS.DONE);
      // Marcou de novo pelo convite: a tela da reunião (pelo "voltar") já mostra o horário novo.
      if (manage.isRebooking.value) manage.refresh();
    } catch (error) {
      if (!isRetriable(error)) requestId = null;
      if (error?.code === 'slot_unavailable') backToTimes();
      else showServerError(error?.code);
    } finally {
      isSubmitting.value = false;
      bookingForm.resetCaptcha();
    }
  };

  // No convite, nome e número já são do contato: só vão se a pessoa digitou (o servidor usa os do convite).
  const contactPayload = () => ({
    name: askName.value ? form.name.trim() : undefined,
    phone: askPhone.value ? bookingForm.phoneValue() : undefined,
    invite_code: invite.invite.value?.code,
    consent: bookingForm.consent(!!page.value.notices_enabled),
    company: form.company,
    form_token: page.value.form_token,
    captcha_token: bookingForm.captchaToken.value || undefined,
  });

  const submitContactRequest = async () => {
    if (isSubmitting.value || isPreview.value) return;
    const isValid = isFormValid({
      askName: askName.value,
      askPhone: askPhone.value,
      emailRequired: false,
    });
    if (!isValid) return;

    isSubmitting.value = true;
    try {
      await formToken.sendWithFreshToken(() =>
        requestContact(slug.value, contactPayload())
      );
      isContactRequested.value = true;
    } catch (error) {
      showServerError(error?.code);
    } finally {
      isSubmitting.value = false;
      bookingForm.resetCaptcha();
    }
  };

  const flow = {
    STEPS,
    manage,
    step,
    page,
    invite,
    slots: slotsApi,
    ...bookingForm,
    days,
    durations,
    duration,
    locations,
    locationType,
    selectedLocation,
    selectedDate,
    selectedSlot,
    slotNotice,
    timeZone,
    clientZone,
    isOtherClock,
    isPreview,
    emailRequired,
    askName,
    askPhone,
    greetingName,
    isChangingPhone,
    isSubmitting,
    result,
    isContactRequested,
    load,
    chooseDuration,
    chooseDay,
    chooseSlot,
    chooseEarliest,
    goBack,
    openNoSlot,
    startPhoneChange,
    submitBooking,
    submitContactRequest,
  };
  provide(FLOW_KEY, flow);
  return flow;
}

export const useFlow = () => inject(FLOW_KEY);
