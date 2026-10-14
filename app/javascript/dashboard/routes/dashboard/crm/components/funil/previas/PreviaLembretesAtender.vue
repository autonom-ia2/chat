<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { lembretesDoModelo } from '../lembretesAtender';

// #1498 — os lembretes de Atender com a Ana, de exemplo: a mensagem que sai e
// quando. Lembrete desligado não aparece.
const props = defineProps({
  modelo: { type: String, default: '' },
  sucesso: { type: String, default: '' },
  ligados: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const L = 'CRM_FUNIL.ATENDER.LEMBRETES';
const nome = computed(() => t('CRM_FUNIL.PREVIA.CLIENTE'));
const valor = computed(() => t(`${L}.VALOR_EXEMPLO`));
const MOMENTOS = {
  progress: [{ quando: `${L}.ANDAMENTO.TITULO`, msg: `${L}.ANDAMENTO.MSG` }],
  resolved_check: [
    { quando: `${L}.RESOLVEU.TITULO`, msg: `${L}.RESOLVEU.MSG` },
  ],
  payment: [
    { quando: `${L}.COBRAR.ANTES`, msg: `${L}.COBRAR.MSG_ANTES` },
    { quando: `${L}.COBRAR.NO_DIA`, msg: `${L}.COBRAR.MSG_NO_DIA` },
    { quando: `${L}.COBRAR.DEPOIS`, msg: `${L}.COBRAR.MSG_DEPOIS` },
  ],
};
const conversa = computed(() =>
  lembretesDoModelo(props.modelo)
    .filter(chave => props.ligados[chave])
    .flatMap(chave => MOMENTOS[chave])
);
</script>

<template>
  <section
    data-previa-lembretes-atender
    class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-teal-2 p-4"
  >
    <template v-for="item in conversa" :key="item.msg">
      <span
        class="self-center rounded-lg bg-n-solid-1 px-2 py-0.5 text-sm text-n-slate-11"
      >
        {{ t(item.quando, { sucesso }) }}
      </span>
      <p
        class="mb-0 max-w-[85%] self-end rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
      >
        {{ t(item.msg, { nome, valor }) }}
      </p>
    </template>
    <p
      v-if="!conversa.length"
      class="mb-0 rounded-xl border border-dashed border-n-slate-6 bg-n-solid-1 p-3 text-[0.9375rem] text-n-slate-11"
    >
      {{ t('CRM_FUNIL.ATENDER.LEMBRETES.DESLIGADOS') }}
    </p>
  </section>
</template>
