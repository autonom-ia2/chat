import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { iaDeAssuntoLigada } from './modoDoAssunto';

// #1676 — a flag crm_avaliar_toda_mensagem da conta, para as telas que dizem o
// que vai acontecer ao salvar (etapa 3 e Confira). As regras puras ficam em
// modoDoAssunto.js.
export {
  FLAG_IA_DE_ASSUNTO,
  chaveDoModo,
  iaDeAssuntoLigada,
  iaSalva,
} from './modoDoAssunto';

export function useIaDeAssunto() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  // Mesma leitura do useFase2: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      iaDeAssuntoLigada(conta.value(contaId.value))
  );
}
