<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { TOM_DO_RAMO } from '../constants/modelosDeRamo';

// #2881 — um ramo de seguro na fileira "Prontos para o seu ramo". Mais baixo que o ModeloCartao (sem o celular): a
// conversa de exemplo aparece ao lado, na criação. O cartão inteiro escolhe o ramo: o "Usar este" se estica sobre ele
// (after:absolute), como no ModeloCartao, e continua um botão só.
const props = defineProps({
  ramo: { type: Object, required: true },
  podeUsar: { type: Boolean, default: false },
  comecando: { type: Boolean, default: false },
  bloqueado: { type: Boolean, default: false },
});

const emit = defineEmits(['usar']);

const { t } = useI18n();
const tituloId = `ramo-${useId()}`;
const base = computed(() => `AGENTS.JORNADA.RAMOS.ITENS.${props.ramo.i18n}`);
const titulo = computed(() => t(`${base.value}.TITULO`));

const usar = () => {
  if (props.comecando || props.bloqueado) return;
  emit('usar', props.ramo.chave);
};
</script>

<template>
  <li
    data-ramo
    class="relative flex flex-col h-full gap-3 p-5 transition shadow-sm rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    :class="[
      podeUsar && !bloqueado ? 'hover:ring-n-blue-11 hover:shadow-md' : '',
      bloqueado ? 'opacity-70' : '',
    ]"
  >
    <div class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-12 shrink-0"
        :class="TOM_DO_RAMO[ramo.tom]"
      >
        <span class="size-6" :class="ramo.icone" />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <h3
          :id="tituloId"
          class="m-0 text-lg font-semibold leading-snug text-n-slate-12"
        >
          {{ titulo }}
        </h3>
        <p class="m-0 text-sm leading-relaxed text-n-slate-11">
          {{ t(`${base}.TEXTO`) }}
        </p>
      </div>
    </div>
    <button
      v-if="podeUsar"
      data-usar-ramo
      type="button"
      :disabled="bloqueado"
      :aria-busy="comecando ? 'true' : undefined"
      :aria-label="t('AGENTS.JORNADA.MODELOS.USAR_ARIA', { titulo })"
      class="inline-flex items-center justify-between w-full gap-2 px-4 mt-auto text-base font-semibold transition min-h-12 rounded-xl bg-n-blue-2 text-n-blue-11 after:absolute after:inset-0 after:rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed"
      @click="usar"
    >
      {{
        comecando
          ? t('AGENTS.JORNADA.COMUM.COMECANDO')
          : t('AGENTS.JORNADA.MODELOS.USAR')
      }}
      <span
        class="i-lucide-arrow-right size-5 shrink-0 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
  </li>
</template>
