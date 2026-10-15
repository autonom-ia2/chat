<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FunilInterruptor from './FunilInterruptor.vue';
import { CHAVE_DO_LEMBRETE, lembretesDoModelo } from './lembretesAtender';

// #1498 — os lembretes de um funil de Atender, cada um numa frase com
// liga/desliga. Sem tempo para escolher: o padrão vale para qualquer negócio.
// Saem no horário de atendimento do funil e a mensagem é escrita olhando a
// conversa de cada cliente.
const props = defineProps({
  modelo: { type: String, default: '' },
  sucesso: { type: String, default: '' },
});
const ligados = defineModel({ type: Object, required: true });

const { t } = useI18n();
const L = 'CRM_FUNIL.ATENDER.LEMBRETES';
const ICONES = {
  progress: 'i-lucide-message-circle-more',
  resolved_check: 'i-lucide-circle-check',
  payment: 'i-lucide-receipt',
};
const lembretes = computed(() =>
  lembretesDoModelo(props.modelo).map(chave => ({
    chave,
    icone: ICONES[chave],
    titulo: t(`${L}.${CHAVE_DO_LEMBRETE[chave]}.TITULO`),
    frase: t(`${L}.${CHAVE_DO_LEMBRETE[chave]}.FRASE`, {
      sucesso: props.sucesso,
    }),
  }))
);
const mudar = (chave, valor) => {
  ligados.value = { ...ligados.value, [chave]: valor };
};
</script>

<template>
  <section class="flex flex-col gap-3" data-lembretes-atender>
    <label
      v-for="item in lembretes"
      :key="item.chave"
      :data-lembrete="item.chave"
      class="flex cursor-pointer items-start gap-4 rounded-2xl border bg-n-solid-1 p-5"
      :class="ligados[item.chave] ? 'border-n-blue-7' : 'border-n-weak'"
    >
      <span
        class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="size-6" :class="item.icone" />
      </span>
      <span class="flex min-w-0 flex-1 flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-11">
          {{ item.titulo }}
        </span>
        <span class="text-base font-semibold leading-relaxed text-n-slate-12">
          {{ item.frase }}
        </span>
      </span>
      <FunilInterruptor
        :model-value="Boolean(ligados[item.chave])"
        :rotulo="item.titulo"
        @update:model-value="mudar(item.chave, $event)"
      />
    </label>
  </section>
</template>
