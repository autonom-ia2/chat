<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1384 — "Sobre este funil" como frase para completar. As ideias completam
// a frase com um toque; a pessoa pode escrever do jeito dela.
const props = defineProps({
  nome: { type: String, default: '' },
  ideias: { type: Array, default: () => [] },
  comNota: { type: Boolean, default: false },
});

const texto = defineModel({ type: String, default: '' });
const nota = defineModel('nota', { type: String, default: '' });

const { t } = useI18n();
const frasesIdeia = computed(() =>
  props.ideias.map(chave => t(`CRM_FUNIL.SOBRE.IDEIAS.${chave}`))
);
</script>

<template>
  <div data-funil-sobre class="flex flex-col gap-4">
    <label for="funil-quando-usar" class="flex flex-col gap-1">
      <span class="text-lg font-semibold text-n-slate-12">
        {{ $t('CRM_FUNIL.SOBRE.FRASE', { nome: nome.trim() || '…' }) }}
      </span>
      <span class="text-[0.9375rem] text-n-slate-11">
        {{ $t('CRM_FUNIL.SOBRE.AJUDA') }}
      </span>
    </label>
    <textarea
      id="funil-quando-usar"
      v-model="texto"
      rows="2"
      maxlength="1000"
      data-pipeline-when-to-use
      :placeholder="$t('CRM_FUNIL.SOBRE.EXEMPLO')"
      class="reset-base !mb-0 !h-auto min-h-[5.5rem] w-full rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-3 text-base leading-7 text-n-slate-12 placeholder:text-n-slate-10 focus:outline focus:outline-2 focus:outline-n-brand"
    />
    <div v-if="frasesIdeia.length" class="flex flex-wrap items-center gap-2">
      <span class="text-sm text-n-slate-11">{{
        $t('CRM_FUNIL.SOBRE.IDEIAS_ROTULO')
      }}</span>
      <button
        v-for="ideia in frasesIdeia"
        :key="ideia"
        type="button"
        data-ideia
        class="min-h-11 rounded-xl bg-n-alpha-2 px-4 text-sm text-n-slate-12 transition hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="texto = ideia"
      >
        {{ ideia }}
      </button>
    </div>
    <label
      v-if="comNota"
      class="mt-2 flex flex-col gap-1 border-t border-n-weak pt-5"
    >
      <span class="text-base font-semibold text-n-slate-12">
        {{ $t('CRM_FUNIL.SOBRE.NOTA') }}
      </span>
      <span class="text-sm text-n-slate-11">{{
        $t('CRM_FUNIL.SOBRE.NOTA_AJUDA')
      }}</span>
      <textarea
        v-model="nota"
        rows="2"
        class="reset-base !mb-0 mt-2 !h-auto min-h-[5.5rem] w-full rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-3 text-base leading-7 text-n-slate-12 placeholder:text-n-slate-10 focus:outline focus:outline-2 focus:outline-n-brand"
        :placeholder="$t('CRM_KANBAN.PIPELINE_DRAWER.DESCRIPTION_PLACEHOLDER')"
      />
    </label>
  </div>
</template>
