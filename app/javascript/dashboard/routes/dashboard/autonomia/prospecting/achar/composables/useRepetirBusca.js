import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { ROTAS } from '../utils/acharRotas';
import { podeIrMaisLonge } from '../utils/acharPedido';

// #2693 — "Buscar de novo" (o Google parou) e "Procurar mais longe" (nada
// achado): uma busca nova no servidor, sem cache, montada da busca salva, e a
// lista dela abre na rota NOVA. Saiu de AcharConfiraPage.vue (trava de 600).
export function useRepetirBusca({ busca, fonte, irPara }) {
  const { t } = useI18n();

  const repetir = async ({ maisLonge }) => {
    try {
      const { searchId } = await fonte.value.repetirBusca({
        busca: busca.value,
        maisLonge,
      });
      await irPara(ROTAS.NOVA, { params: { searchId }, estado: 'buscando' });
    } catch {
      useAlert(t('PROSPECTING_ACHAR.COMUM.ERRO_BUSCAR_DE_NOVO'));
    }
  };

  return {
    buscarDeNovo: () => repetir({ maisLonge: false }),
    procurarMaisLonge: () => repetir({ maisLonge: true }),
    maisLonge: computed(() => podeIrMaisLonge(busca.value?.pedido)),
  };
}
