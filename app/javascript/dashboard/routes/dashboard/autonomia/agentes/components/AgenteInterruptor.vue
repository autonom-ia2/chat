<script setup>
import { useI18n } from 'vue-i18n';

// #1181 — interruptor de estado do herói do agente (protótipo T07/T15): role=switch, alvo de 44 px
// e o estado escrito ao lado (Atendendo / Parado). O nome acessível diz o que ele controla; o
// estado vai em aria-checked. Quem usa decide o que acontece (parar pede confirmação; voltar a
// atender passa pela escolha de canal), por isso ele só emite o valor pedido.
const props = defineProps({
  ligado: { type: Boolean, required: true },
  rotulo: { type: String, required: true },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['alternar']);

const { t } = useI18n();

const alternar = () => {
  if (props.desabilitado) return;
  emit('alternar', !props.ligado);
};
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="ligado ? 'true' : 'false'"
    :aria-label="rotulo"
    :disabled="desabilitado"
    class="inline-flex items-center gap-3 px-2 text-sm font-semibold text-white rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-60"
    @click="alternar"
  >
    <span
      aria-hidden="true"
      class="relative inline-flex items-center h-7 transition rounded-full w-12 shrink-0"
      :class="ligado ? 'bg-n-teal-9' : 'bg-white/30'"
    >
      <span
        class="absolute bg-white rounded-full shadow size-5 transition-all"
        :class="ligado ? 'start-6' : 'start-1'"
      />
    </span>
    <span aria-hidden="true">
      {{
        ligado
          ? t('AGENTS.JORNADA.STATUS.ATENDENDO')
          : t('AGENTS.JORNADA.STATUS.PARADO')
      }}
    </span>
  </button>
</template>
