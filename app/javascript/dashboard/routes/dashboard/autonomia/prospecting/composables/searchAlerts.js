import { useAlert } from 'dashboard/composables';

// Mostra o erro que a API devolveu ou, na falta dele, a mensagem da tela.
export const alertError = (error, fallbackMessage) => {
  useAlert(error?.response?.data?.error || fallbackMessage);
};
