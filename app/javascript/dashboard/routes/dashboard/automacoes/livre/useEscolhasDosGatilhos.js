import { computed, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2499 (F6+F8) — o que os campos do gatilho mostram: as etapas de cada funil
// (agrupadas pelo funil), os funis e os campos de data do card e do contato.
// Vêm das mesmas APIs e stores que o CRM e os campos personalizados já usam.
const comNome = (lista, rotulo = 'name') =>
  (lista || []).map(item => ({ value: item.id, label: item[rotulo] }));

const camposDeData = lista =>
  (lista || [])
    .filter(item => item.attribute_display_type === 'date')
    .map(item => ({
      value: item.attribute_key,
      label: item.attribute_display_name,
    }));

export function useEscolhasDosGatilhos() {
  const store = useStore();
  const atributosDo = useMapGetter('attributes/getAttributesByModel');
  const funis = ref([]);
  const etapasPorFunil = ref({});

  const carregar = async () => {
    store.dispatch('attributes/get');
    const { data } = await CrmKanbanAPI.getPipelines();
    funis.value = data.payload || [];
    const listas = await Promise.all(
      funis.value.map(funil => CrmKanbanAPI.getStages(funil.id))
    );
    etapasPorFunil.value = Object.fromEntries(
      funis.value.map((funil, i) => [funil.id, listas[i].data.payload || []])
    );
  };

  const escolhas = computed(() => ({
    funis: comNome(funis.value),
    etapas: funis.value.map(funil => ({
      label: funil.name,
      options: comNome(etapasPorFunil.value[funil.id]),
    })),
    camposDoCard: camposDeData(atributosDo.value('card_attribute')),
    camposDoContato: camposDeData(atributosDo.value('contact_attribute')),
  }));

  return { escolhas, carregar };
}
