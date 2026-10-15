<script setup>
// Calendário Ouro — no celular, a semana numa faixa no topo do "Meu dia".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { diasDaSemana, formatarDia, somarDias } from './tempoNaConta';

const props = defineProps({
  dia: { type: String, required: true },
  hoje: { type: String, required: true },
  idioma: { type: String, required: true },
  marcas: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['escolher']);
const { t } = useI18n();
const dias = computed(() => diasDaSemana(props.dia));
const curto = chave => formatarDia(chave, props.idioma, { weekday: 'short' });
</script>

<template>
  <div data-faixa-semana class="flex items-center gap-1">
    <button
      type="button"
      class="grid size-11 shrink-0 place-items-center rounded-xl text-n-slate-11"
      :aria-label="t('CRM_CALENDARIO.NAV.SEMANA_ANTERIOR')"
      @click="emit('escolher', somarDias(dia, -7))"
    >
      <span
        class="i-lucide-chevron-left size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
    <div class="grid min-w-0 flex-1 grid-cols-7 gap-1">
      <button
        v-for="chave in dias"
        :key="chave"
        type="button"
        :aria-pressed="chave === dia"
        class="flex min-h-14 flex-col items-center justify-center rounded-xl text-xs transition"
        :class="
          chave === dia
            ? 'bg-n-slate-12 text-n-solid-1'
            : chave === hoje
              ? 'text-n-blue-11 ring-1 ring-inset ring-n-blue-8'
              : 'text-n-slate-11'
        "
        @click="emit('escolher', chave)"
      >
        <span class="capitalize">{{ curto(chave).replace('.', '') }}</span>
        <span class="text-base font-semibold tabular-nums">{{
          Number(chave.slice(8))
        }}</span>
        <span
          class="size-1 rounded-full"
          :class="
            marcas[chave] === 'atrasado'
              ? 'bg-n-ruby-9'
              : marcas[chave]
                ? chave === dia
                  ? 'bg-n-solid-1'
                  : 'bg-n-blue-9'
                : 'bg-transparent'
          "
          aria-hidden="true"
        />
      </button>
    </div>
    <button
      type="button"
      class="grid size-11 shrink-0 place-items-center rounded-xl text-n-slate-11"
      :aria-label="t('CRM_CALENDARIO.NAV.SEMANA_SEGUINTE')"
      @click="emit('escolher', somarDias(dia, 7))"
    >
      <span
        class="i-lucide-chevron-right size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
  </div>
</template>
