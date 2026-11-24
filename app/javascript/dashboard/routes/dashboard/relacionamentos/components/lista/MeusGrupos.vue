<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PilulasDeGrupo from '../comum/PilulasDeGrupo.vue';

// #3168 — "Meus grupos": os grupos que a pessoa guardou, em pílulas sem número,
// na ordem em que foram criados. Com um escolhido, a frase de quem entra nele
// (`resumo`, lista/resumoDoGrupo.js) e o que dá para fazer com ele: "Mudar
// quem entra", "Trocar o nome" e "Apagar grupo". Sem nenhum guardado, um
// cartão com uma frase e um botão, "Escolher quem entra" (`comecar`): a tela
// some com a lista e o botão abre a gaveta "Mais filtros".
const props = defineProps({
  // [{ id, nome, visao, grupo, busca, filtros }]
  guardados: { type: Array, required: true },
  modelValue: { type: String, default: '' },
  resumo: { type: String, default: '' },
});
const emit = defineEmits([
  'update:modelValue',
  'mudar',
  'renomear',
  'apagar',
  'comecar',
]);

const { t } = useI18n();
const MG = 'RELACIONAMENTOS.LISTA.MEUS_GRUPOS';
const pilulas = computed(() =>
  props.guardados.map(({ id, nome }) => ({ id, nome }))
);
</script>

<template>
  <div class="flex flex-col min-w-0" data-relacionamentos="meus-grupos">
    <template v-if="guardados.length">
      <PilulasDeGrupo
        :grupos="pilulas"
        :rotulo="t(`${MG}.CHAVE`)"
        :model-value="modelValue"
        @update:model-value="emit('update:modelValue', $event)"
      />
      <p
        v-if="modelValue && resumo"
        class="m-0 mt-3 text-sm break-words text-n-slate-12"
        data-relacionamentos="resumo-do-grupo"
      >
        <span class="font-medium">{{ t(`${MG}.QUEM_ENTRA`) }}</span>
        {{ resumo }}
      </p>
      <div
        v-if="modelValue"
        class="flex flex-wrap items-center mt-1 gap-x-5"
        data-relacionamentos="acoes-do-grupo"
      >
        <Button
          link
          sm
          type="button"
          class="min-h-11"
          icon="i-lucide-sliders-horizontal"
          aria-haspopup="dialog"
          :label="t(`${MG}.MUDAR`)"
          @click="emit('mudar')"
        />
        <Button
          link
          sm
          type="button"
          class="min-h-11"
          icon="i-lucide-pencil"
          aria-haspopup="dialog"
          :label="t(`${MG}.RENOMEAR`)"
          @click="emit('renomear')"
        />
        <Button
          link
          sm
          ruby
          type="button"
          class="min-h-11"
          icon="i-lucide-trash-2"
          aria-haspopup="dialog"
          :label="t(`${MG}.APAGAR`)"
          @click="emit('apagar')"
        />
      </div>
    </template>
    <div
      v-else
      class="flex flex-col items-center gap-4 px-6 py-10 text-center rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      data-relacionamentos="meus-grupos-vazio"
    >
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ t(`${MG}.VAZIO`) }}
      </p>
      <Button
        size="lg"
        icon="i-lucide-sliders-horizontal"
        aria-haspopup="dialog"
        data-relacionamentos="escolher-quem-entra"
        :label="t(`${MG}.ESCOLHER_QUEM_ENTRA`)"
        @click="emit('comecar')"
      />
    </div>
  </div>
</template>
