<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreEtapa from './LivreEtapa.vue';
import LivreMarcar from './LivreMarcar.vue';
import {
  MAXIMO_DE_EMPRESAS,
  buscaQueServe,
  comFaz,
  opcaoDaBusca,
  quantasServe,
} from '../prospeccao';

// #2414 G21 (#2706) — o passo "prospecção" inteiro: o que fazer e, para
// buscar, a busca do histórico da Prospecção, quantas empresas, a etapa do
// card e as etiquetas do contato. O servidor confere tudo de novo ao salvar,
// inclusive que o gatilho roda sozinho e que a busca é de quem salva.
const props = defineProps({
  modelValue: { type: Object, required: true },
  etiquetas: { type: Array, default: () => [] },
  // [{ label: funil, options: [{ value: id, label: etapa }] }]
  etapas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const P = 'AUTOMACAO_LIVRE.PROSPECCAO';
const idFaz = useId();
const idBusca = useId();

const passo = computed(() => props.modelValue);
const buscar = computed(() => passo.value.faz === 'buscar');
const mudar = mudanca =>
  emit('update:modelValue', { ...passo.value, ...mudanca });

const opcoesDoFaz = computed(() => [
  { value: 'recusar', label: t(`${P}.RECUSAR`) },
  { value: 'buscar', label: t(`${P}.BUSCAR`) },
]);
const escolherFaz = faz => emit('update:modelValue', comFaz(passo.value, faz));

// As buscas mais recentes do histórico que esta pessoa vê (a mesma lista da
// tela da Prospecção, que já filtra pela permissão). Lidas uma vez, quando o
// passo passa a buscar. A busca já salva no passo que não está entre as
// recentes é lida pelo id: só some de verdade quando a Prospecção não a acha.
const buscas = ref([]);
const falhou = ref(false);
const sumiu = ref(false);
let lidas = false;
const lerSalva = async id => {
  try {
    const { data } = await AutonomiaProspectingAPI.getSearch(id);
    const salva = data.payload;
    if (salva && buscaQueServe(salva)) buscas.value = [...buscas.value, salva];
    else sumiu.value = true;
  } catch {
    sumiu.value = true;
  }
};
const lerBuscas = async () => {
  lidas = true;
  try {
    const { data } = await AutonomiaProspectingAPI.getSearches({
      per_page: 50,
    });
    buscas.value = (data.payload || []).filter(buscaQueServe);
  } catch {
    falhou.value = true;
    return;
  }
  const id = passo.value.busca_id;
  if (Number.isInteger(id) && !buscas.value.some(busca => busca.id === id))
    await lerSalva(id);
};
watch(
  buscar,
  vale => {
    if (vale && !lidas) lerBuscas();
  },
  { immediate: true }
);
const opcoesDaBusca = computed(() =>
  buscas.value.map(busca => opcaoDaBusca(busca, t))
);
const buscaSumiu = computed(
  () =>
    sumiu.value &&
    !buscas.value.some(busca => busca.id === passo.value.busca_id)
);
const quantasFora = computed(
  () => passo.value.quantas != null && !quantasServe(passo.value.quantas)
);

const escolherBusca = id => {
  sumiu.value = false;
  mudar({ busca_id: id });
};

const mudarQuantas = texto => {
  const numero = Number(texto);
  mudar({ quantas: texto === '' || Number.isNaN(numero) ? null : numero });
};
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="prospeccao">
    <div class="flex flex-col gap-1.5">
      <label :for="idFaz" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.CAMPOS.FAZ') }}
      </label>
      <ChoiceSelect
        data-prospeccao-faz
        :model-value="passo.faz"
        :trigger-id="idFaz"
        :aria-label="$t('AUTOMACAO_LIVRE.CAMPOS.FAZ')"
        :options="opcoesDoFaz"
        @update:model-value="escolherFaz"
      />
    </div>

    <p v-if="!buscar" class="mb-0 text-sm text-n-slate-11">
      {{ $t(`${P}.RECUSAR_DICA`) }}
    </p>

    <template v-else>
      <p
        data-prospeccao-so-recorrente
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${P}.SO_RECORRENTE`) }}
      </p>

      <div class="flex flex-col gap-1.5">
        <label :for="idBusca" class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.CAMPOS.BUSCA_ID') }}
        </label>
        <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${P}.BUSCA_DICA`) }}</p>
        <ChoiceSelect
          data-prospeccao-busca
          :model-value="passo.busca_id ?? ''"
          :trigger-id="idBusca"
          :aria-label="$t('AUTOMACAO_LIVRE.CAMPOS.BUSCA_ID')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDaBusca"
          @update:model-value="escolherBusca"
        />
        <p
          v-if="falhou"
          data-prospeccao-falhou
          role="alert"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ $t(`${P}.ERRO_BUSCAS`) }}
        </p>
        <p
          v-else-if="buscaSumiu"
          data-prospeccao-busca-sumiu
          role="status"
          class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
        >
          {{ $t(`${P}.BUSCA_SUMIU`) }}
        </p>
      </div>

      <Input
        data-prospeccao-quantas
        type="number"
        :model-value="passo.quantas ?? ''"
        :label="$t('AUTOMACAO_LIVRE.CAMPOS.QUANTAS')"
        :message="
          $t(quantasFora ? `${P}.QUANTAS_FORA` : `${P}.QUANTAS_DICA`, {
            maximo: MAXIMO_DE_EMPRESAS,
          })
        "
        :message-type="quantasFora ? 'error' : 'info'"
        @update:model-value="mudarQuantas"
      />

      <LivreEtapa
        :rotulo="$t('AUTOMACAO_LIVRE.CAMPOS.ETAPA_ID')"
        :model-value="passo.etapa_id"
        :grupos="etapas"
        @update:model-value="id => mudar({ etapa_id: id })"
      />

      <div class="flex flex-col gap-1.5">
        <LivreMarcar
          :rotulo="$t(`${P}.ETIQUETAS_ROTULO`)"
          :opcoes="etiquetas"
          :model-value="passo.etiquetas || []"
          @update:model-value="novas => mudar({ etiquetas: novas })"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${P}.ETIQUETAS_DICA`) }}
        </p>
      </div>
    </template>
  </div>
</template>
