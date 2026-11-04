import { computed } from 'vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

// #2448: webhook e transcrição por e-mail mandam a conversa para fora, como uma integração. Mexer numa regra que tem
// (ou vai ter) uma delas pede integration_manage (admin sempre); o servidor barra e a tela avisa antes.
export const SAIDA_EXTERNA = ['send_webhook_event', 'send_email_transcript'];

export const usaSaidaExterna = actions =>
  (actions || []).some(({ action_name }) =>
    SAIDA_EXTERNA.includes(action_name)
  );

export function useSaidaExterna() {
  const podeIntegrar = usePermissionGranted('integration_manage');
  const travada = (...listas) =>
    !podeIntegrar.value && listas.some(lista => usaSaidaExterna(lista));

  return { podeIntegrar: computed(() => podeIntegrar.value), travada };
}
