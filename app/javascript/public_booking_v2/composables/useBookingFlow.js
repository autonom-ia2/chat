import { computed, inject, provide, ref } from 'vue';
import { createBooking, getPage, requestContact } from '../api';
import { applyBrandColor } from '../helpers/brand';
import { bookingDays, dateInZone, isValidTimeZone } from '../helpers/datetime';
import { useBookingForm } from './useBookingForm';
import { useInvite } from './useInvite';
import { useSlots } from './useSlots';

export const STEPS = Object.freeze({
  LOADING: 'loading',
  NOT_FOUND: 'not_found',
  ERROR: 'error',
  PAUSED: 'paused',
  ALREADY: 'already',
  DATE: 'date',
  TIME: 'time',
  DETAILS: 'details',
  CONFIRM: 'confirm',
  DONE: 'done',
  NO_SLOT: 'no_slot',
});

const FLOW_KEY = Symbol('bookingFlow');

// `/book/:slug` (link público ou de pessoa) e `/b/:code` (link do cliente). `?preview=` só no link de página.
export const parseRoute = (pathname, search) => {
  const parts = String(pathname || '')
    .split('/')
    .filter(Boolean);
  const preview = new URLSearchParams(search || '').get('preview') || null;
  if (parts[0] === 'b' && parts[1]) return { code: parts[1], slug: null };
  if (parts[0] === 'book' && parts[1]) {
    return { code: null, slug: parts[1], preview };
  }
  return { code: null, slug: null };
};

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
  const isSubmitting = ref(false);
  const result = ref(null);
  const isContactRequested = ref(false);

  const invite = useInvite();
  const slotsApi = useSlots({ slug, duration });
  const bookingForm = useBookingForm();
  const { form } = bookingForm;

  const timeZone = computed(() => page.value?.timezone || '');
  const days = computed(() =>
    page.value
      ? bookingDays(timeZone.value, page.value.booking_window_days)
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
  // No convite o nome vem do contato; o campo só aparece se faltar ou se o servidor recusar o nome.
  const askName = computed(
    () =>
      !invite.isInvite.value ||
      !invite.firstName.value ||
      !!bookingForm.fieldErrors.name
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

  const startBooking = () => {
    goTo(STEPS.DATE);
    slotsApi.loadNextSlot();
  };

  const showPage = data => {
    page.value = data;
    applyBrandColor(data?.brand?.color);
    if (data?.paused) return goTo(STEPS.PAUSED);
    if (!isValidTimeZone(data?.timezone)) return goTo(STEPS.ERROR);

    duration.value = data.duration_minutes;
    locationType.value = locations.value[0]?.type || null;
    if (invite.firstName.value) form.name = invite.firstName.value;
    if (invite.isScheduled.value) return goTo(STEPS.ALREADY);
    return startBooking();
  };

  const load = async () => {
    step.value = STEPS.LOADING;
    try {
      if (route.code) {
        const data = await invite.load(route.code);
        slug.value = data?.page_slug || null;
      }
      if (!slug.value) return goTo(STEPS.NOT_FOUND);
      return showPage(await getPage(slug.value, route.preview));
    } catch (error) {
      return goTo(error?.status === 404 ? STEPS.NOT_FOUND : STEPS.ERROR);
    }
  };

  const chooseDuration = minutes => {
    duration.value = minutes;
    slotsApi.loadNextSlot();
  };

  const chooseDay = date => {
    selectedDate.value = date;
    selectedSlot.value = '';
    slotNotice.value = '';
    goTo(STEPS.TIME);
    slotsApi.loadSlots(date);
  };

  const chooseSlot = iso => {
    selectedSlot.value = iso;
    slotNotice.value = '';
    goTo(invite.isInvite.value ? STEPS.CONFIRM : STEPS.DETAILS);
  };

  const chooseEarliest = () => {
    const iso = slotsApi.nextSlot.value;
    if (!iso) return;
    selectedDate.value = dateInZone(new Date(iso), timeZone.value);
    chooseSlot(iso);
  };

  const goBack = () => {
    if (step.value === STEPS.DETAILS || step.value === STEPS.CONFIRM) {
      return chooseDay(selectedDate.value);
    }
    return goTo(STEPS.DATE);
  };

  const openNoSlot = () => goTo(STEPS.NO_SLOT);

  const startPhoneChange = () => {
    isChangingPhone.value = true;
  };

  const backToTimes = () => {
    slotNotice.value = 'BOOKING_V2.ERRORS.SLOT_UNAVAILABLE';
    selectedSlot.value = '';
    step.value = STEPS.TIME;
    slotsApi.loadSlots(selectedDate.value);
    slotsApi.loadNextSlot();
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
  });

  const handleBookingError = error => {
    if (error?.code === 'slot_unavailable') return backToTimes();
    const field = bookingForm.applyServerError(error?.code);
    if (field === 'phone') isChangingPhone.value = true;
    return null;
  };

  const submitBooking = async () => {
    if (isSubmitting.value) return;
    const isValid = bookingForm.validate({
      askName: askName.value,
      askPhone: askPhone.value,
      emailRequired: emailRequired.value,
      captchaRequired: captchaRequired.value,
    });
    if (!isValid) return;

    isSubmitting.value = true;
    try {
      result.value = await createBooking(slug.value, bookingPayload());
      goTo(STEPS.DONE);
    } catch (error) {
      handleBookingError(error);
    } finally {
      isSubmitting.value = false;
      bookingForm.resetCaptcha();
    }
  };

  const submitContactRequest = async () => {
    if (isSubmitting.value) return;
    const isValid = bookingForm.validate({
      askName: true,
      askPhone: true,
      emailRequired: false,
      captchaRequired: captchaRequired.value,
    });
    if (!isValid) return;

    isSubmitting.value = true;
    try {
      await requestContact(slug.value, {
        name: form.name.trim(),
        phone: bookingForm.phoneValue(),
        consent: bookingForm.consent(!!page.value.notices_enabled),
        company: form.company,
        form_token: page.value.form_token,
        captcha_token: bookingForm.captchaToken.value || undefined,
      });
      isContactRequested.value = true;
    } catch (error) {
      bookingForm.applyServerError(error?.code);
    } finally {
      isSubmitting.value = false;
      bookingForm.resetCaptcha();
    }
  };

  const flow = {
    STEPS,
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
