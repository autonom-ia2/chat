import { reactive, ref } from 'vue';
import {
  DEFAULT_COUNTRY_CODE,
  isPlausiblePhone,
  looksLikeEmail,
  toInternational,
} from '../helpers/phone';

export const CONSENT_TEXT_KEY = 'booking_v2.consent.whatsapp_notices';

// Erros do servidor (422 `{ error }`) que apontam para um campo.
const FIELD_ERRORS = {
  invalid_name: ['name', 'BOOKING_V2.ERRORS.INVALID_NAME'],
  invalid_phone: ['phone', 'BOOKING_V2.ERRORS.INVALID_PHONE'],
  invalid_email: ['email', 'BOOKING_V2.ERRORS.INVALID_EMAIL'],
  email_required: ['email', 'BOOKING_V2.ERRORS.EMAIL_REQUIRED'],
};

// Dados que a pessoa digita: só nome e WhatsApp são obrigatórios; e-mail só quando o local exige (RA-18).
export function useBookingForm() {
  const form = reactive({
    name: '',
    countryCode: DEFAULT_COUNTRY_CODE,
    phone: '',
    email: '',
    company: '', // honeypot: gente não vê, robô preenche
  });
  const fieldErrors = reactive({ name: '', phone: '', email: '' });
  const formError = ref('');
  const captchaToken = ref('');
  const captchaKey = ref(0);

  const clearErrors = () => {
    fieldErrors.name = '';
    fieldErrors.phone = '';
    fieldErrors.email = '';
    formError.value = '';
  };

  const validate = ({ askName, askPhone, emailRequired, captchaRequired }) => {
    clearErrors();
    if (askName && !form.name.trim()) {
      fieldErrors.name = 'BOOKING_V2.ERRORS.INVALID_NAME';
    }
    if (askPhone && !isPlausiblePhone(form.countryCode, form.phone)) {
      fieldErrors.phone = 'BOOKING_V2.ERRORS.INVALID_PHONE';
    }
    const email = form.email.trim();
    if (emailRequired && !email) {
      fieldErrors.email = 'BOOKING_V2.ERRORS.EMAIL_REQUIRED';
    } else if (email && !looksLikeEmail(email)) {
      fieldErrors.email = 'BOOKING_V2.ERRORS.INVALID_EMAIL';
    }
    const hasFieldError =
      !!fieldErrors.name || !!fieldErrors.phone || !!fieldErrors.email;
    if (!hasFieldError && captchaRequired && !captchaToken.value) {
      formError.value = 'BOOKING_V2.ERRORS.CAPTCHA';
    }
    return !hasFieldError && !formError.value;
  };

  // Devolve o campo atingido (ou null) e já mostra a mensagem certa.
  const applyServerError = code => {
    const fieldError = FIELD_ERRORS[code];
    if (fieldError) {
      const [field, key] = fieldError;
      fieldErrors[field] = key;
      return field;
    }
    formError.value =
      code === 'too_many_open'
        ? 'BOOKING_V2.ERRORS.TOO_MANY_OPEN'
        : 'BOOKING_V2.ERRORS.BOOKING_FAILED';
    return null;
  };

  // O token do hCaptcha vale uma vez: depois de cada envio o widget recomeça.
  const resetCaptcha = () => {
    captchaToken.value = '';
    captchaKey.value += 1;
  };

  const phoneValue = () => toInternational(form.countryCode, form.phone);

  const consent = accepted => ({ accepted, text_key: CONSENT_TEXT_KEY });

  return {
    form,
    fieldErrors,
    formError,
    captchaToken,
    captchaKey,
    clearErrors,
    validate,
    applyServerError,
    resetCaptcha,
    phoneValue,
    consent,
  };
}
