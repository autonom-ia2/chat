import { computed, ref } from 'vue';
import { getInvite, markInviteViewed } from '../api';

// Link do cliente `/b/:code` (J1-A2): o convite diz de qual página é, o primeiro nome e o telefone mascarado.
export function useInvite() {
  const invite = ref(null);
  let viewedSent = false;

  const load = async code => {
    invite.value = await getInvite(code);
    return invite.value;
  };

  // Uma vez só, depois do primeiro render. É medição ("aberto" no card): se falhar, a pessoa continua
  // agendando normalmente, então o erro não interrompe a página.
  const markViewed = async () => {
    if (viewedSent || !invite.value?.code) return;
    viewedSent = true;
    try {
      await markInviteViewed(invite.value.code);
    } catch (error) {
      // Sem retentativa: o servidor conta aberturas e uma perdida não muda nada para o cliente.
    }
  };

  return {
    invite,
    isInvite: computed(() => !!invite.value),
    firstName: computed(() => invite.value?.contact_first_name || ''),
    phoneMasked: computed(() => invite.value?.phone_masked || ''),
    isScheduled: computed(() => invite.value?.state === 'scheduled'),
    load,
    markViewed,
  };
}
