<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { DESTINOS, LISTA_DE_DESTINOS } from '../../trazer/destinos';

// #2894 — uma coluna da planilha e para onde ela vai ("Cel" → Telefone), com
// Trocar. Coluna que o sistema não conhecia vira "informação da pessoa" e
// ganha também Não guardar.
const props = defineProps({
  coluna: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['trocar']);

const { t } = useI18n();
const CHAVES_DOS_DESTINOS = {
  [DESTINOS.NOME]: 'RELACIONAMENTOS_TRAZER.DESTINOS.NOME',
  [DESTINOS.TELEFONE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.TELEFONE',
  [DESTINOS.TELEFONE_DA_EMPRESA]:
    'RELACIONAMENTOS_TRAZER.DESTINOS.TELEFONE_DA_EMPRESA',
  [DESTINOS.EMAIL]: 'RELACIONAMENTOS_TRAZER.DESTINOS.EMAIL',
  [DESTINOS.EMPRESA]: 'RELACIONAMENTOS_TRAZER.DESTINOS.EMPRESA',
  [DESTINOS.CIDADE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.CIDADE',
  [DESTINOS.CLIENTE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.CLIENTE',
  [DESTINOS.INFORMACAO]: 'RELACIONAMENTOS_TRAZER.DESTINOS.INFORMACAO',
  [DESTINOS.NAO_GUARDAR]: 'RELACIONAMENTOS_TRAZER.DESTINOS.NAO_GUARDAR',
};
const trocando = ref(false);

const nomeDoDestino = destino => t(CHAVES_DOS_DESTINOS[destino]);

const opcoes = computed(() =>
  LISTA_DE_DESTINOS.map(destino => ({
    value: destino,
    label: nomeDoDestino(destino),
  }))
);

const naoGuarda = computed(() => props.coluna.destino === DESTINOS.NAO_GUARDAR);
const virouInformacao = computed(
  () => props.coluna.destino === DESTINOS.INFORMACAO
);

const escolher = destino => {
  trocando.value = false;
  if (destino !== props.coluna.destino)
    emit('trocar', props.coluna.nome, destino);
};
</script>

<template>
  <li
    :data-coluna="coluna.nome"
    class="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between"
  >
    <p class="flex flex-wrap items-center gap-2 m-0 text-base text-n-slate-12">
      <template v-if="virouInformacao">
        {{
          t('RELACIONAMENTOS_TRAZER.GUARDAR.VIRA_INFORMACAO', {
            coluna: coluna.nome,
          })
        }}
      </template>
      <template v-else-if="naoGuarda">
        {{
          t('RELACIONAMENTOS_TRAZER.GUARDAR.NAO_VOU_GUARDAR', {
            coluna: coluna.nome,
          })
        }}
      </template>
      <template v-else>
        <span class="font-medium">{{ coluna.nome }}</span>
        <span class="sr-only">{{
          t('RELACIONAMENTOS_TRAZER.GUARDAR.VAI_PARA')
        }}</span>
        <span
          class="i-lucide-arrow-right size-4 text-n-slate-10 rtl:rotate-180"
          aria-hidden="true"
        />
        <span>{{ nomeDoDestino(coluna.destino) }}</span>
      </template>
    </p>
    <div class="flex flex-wrap items-center gap-2">
      <div v-if="trocando" class="w-64 max-w-full">
        <ChoiceSelect
          :model-value="coluna.destino"
          :options="opcoes"
          :aria-label="
            t('RELACIONAMENTOS_TRAZER.GUARDAR.ROTULO_TROCAR', {
              coluna: coluna.nome,
            })
          "
          @update:model-value="escolher"
        />
      </div>
      <Button
        v-else
        ghost
        slate
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.TROCAR')"
        :aria-label="
          t('RELACIONAMENTOS_TRAZER.GUARDAR.ROTULO_TROCAR', {
            coluna: coluna.nome,
          })
        "
        :disabled="ocupado"
        @click="trocando = true"
      />
      <Button
        v-if="virouInformacao && !trocando"
        ghost
        slate
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.NAO_GUARDAR')"
        :disabled="ocupado"
        @click="escolher(DESTINOS.NAO_GUARDAR)"
      />
    </div>
  </li>
</template>
