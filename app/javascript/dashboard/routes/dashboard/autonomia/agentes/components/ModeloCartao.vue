<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CelularConversa from './CelularConversa.vue';
import AgenteErro from './AgenteErro.vue';

// #1181 (protótipo T01 e gaveta "Criar agente") — um modelo pronto com a conversa de exemplo num
// celular. O cartão inteiro escolhe o modelo: o "Usar este" se estica sobre o cartão (after:absolute),
// e continua sendo um botão só, com teclado e rótulo. Os três modelos têm o mesmo peso (contorno).
const props = defineProps({
  modelo: { type: Object, required: true },
  podeUsar: { type: Boolean, default: false },
  comecando: { type: Boolean, default: false },
  bloqueado: { type: Boolean, default: false },
  falhou: { type: Boolean, default: false },
});

const emit = defineEmits(['usar']);

const { t } = useI18n();
const tituloId = `modelo-${useId()}`;
const base = computed(() => `AGENTS.JORNADA.MODELOS.${props.modelo.i18n}`);
const titulo = computed(() => t(`${base.value}.TITULO`));

const exemplo = computed(() => [
  {
    de: 'cliente',
    texto: t(`${base.value}.CLIENTE`),
    hora: props.modelo.horario,
  },
  {
    de: 'agente',
    texto: t(`${base.value}.AGENTE`),
    hora: props.modelo.horario,
  },
]);

const usar = () => {
  if (props.comecando || props.bloqueado) return;
  emit('usar', props.modelo.chave);
};
</script>

<template>
  <li
    class="relative flex flex-col gap-4 p-5 transition shadow-sm rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    :class="[
      podeUsar && !bloqueado ? 'hover:ring-n-blue-11 hover:shadow-md' : '',
      bloqueado ? 'opacity-60' : '',
    ]"
  >
    <div class="flex flex-col gap-1">
      <h3 :id="tituloId" class="m-0 text-lg font-semibold text-n-slate-12">
        {{ titulo }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${base}.TEXTO`) }}
      </p>
    </div>
    <CelularConversa
      tamanho="mini"
      :mensagens="exemplo"
      :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
      :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
    />
    <button
      v-if="podeUsar"
      data-usar
      type="button"
      :disabled="bloqueado"
      :aria-busy="comecando ? 'true' : undefined"
      :aria-label="t('AGENTS.JORNADA.MODELOS.USAR_ARIA', { titulo })"
      class="mt-auto inline-flex items-center justify-center w-full gap-2 px-5 text-base font-semibold transition min-h-12 rounded-xl bg-n-solid-1 text-n-blue-11 ring-1 ring-inset ring-n-blue-9 hover:bg-n-blue-2 after:absolute after:inset-0 after:rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed"
      @click="usar"
    >
      {{
        comecando
          ? t('AGENTS.JORNADA.COMUM.COMECANDO')
          : t('AGENTS.JORNADA.MODELOS.USAR')
      }}
    </button>
    <AgenteErro
      v-if="falhou"
      class="relative z-10"
      :titulo="t('AGENTS.JORNADA.ERRO.COMECAR_MODELO')"
      :garantia="t('AGENTS.JORNADA.ERRO.COMECAR_MODELO_GARANTIA')"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="usar"
    />
  </li>
</template>
