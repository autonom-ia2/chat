<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import { rotuloDaBase, rotuloDoTipo } from '../../utils/baseDoAgente';

// #1429 F3 — a linha "Base de seguros" no resumo da página do agente. Só leitura: diz com que base o agente trabalha
// (tipo e data) ou que ele está sem base. Para quem gerencia, quando há base nova, o aviso e "Atualizar com a nova
// base" (abre a gaveta do antes e depois); logo depois de atualizar, "Desfazer". Quem só vê lê a linha, sem aviso nem
// botão. A Lia (cotação) não recebe a linha: quem decide é a página.
const props = defineProps({
  // { situacao, atual, nova, pode_atualizar, desfazer } da API (useBaseDoAgente)
  base: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
  erroDesfazer: { type: Boolean, default: false },
  // O motivo do servidor quando o Desfazer não vale mais (409); vazio, o aviso genérico.
  textoErroDesfazer: { type: String, default: '' },
});

const emit = defineEmits(['atualizar', 'desfazer']);

const { t, locale } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.BASE';
const tituloId = `base-${useId()}`;

const textoAtual = computed(() =>
  props.base.atual
    ? rotuloDaBase(props.base.atual, t, locale.value)
    : t(`${NS}.SEM_BASE`, { nome: props.nome })
);

const nova = computed(() =>
  props.podeGerenciar && props.base.pode_atualizar ? props.base.nova : null
);
const textoNova = computed(() => {
  if (!nova.value) return '';
  const valores = {
    tipo: rotuloDoTipo(nova.value.segmento, t),
    base: rotuloDaBase(nova.value, t, locale.value),
  };
  return props.base.situacao === 'conta_mudou'
    ? t(`${NS}.NOVA_CONTA_MUDOU`, valores)
    : t(`${NS}.NOVA`, valores);
});

const podeDesfazer = computed(
  () => props.podeGerenciar && Boolean(props.base.desfazer)
);
</script>

<template>
  <div
    data-linha="base"
    role="group"
    :aria-labelledby="tituloId"
    class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
  >
    <div class="flex items-start flex-1 min-w-0 gap-3">
      <span
        class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
        aria-hidden="true"
      >
        <span class="i-lucide-shield-check size-5 text-n-slate-11" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-1">
        <h3 :id="tituloId" class="m-0 text-sm font-semibold text-n-slate-11">
          {{ t(`${NS}.TITULO`) }}
        </h3>
        <p data-base-atual class="m-0 text-sm text-n-slate-12">
          {{ textoAtual }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.EXPLICA`, { nome }) }}
        </p>
        <p
          v-if="nova"
          data-base-nova
          class="flex items-start gap-1.5 px-2.5 py-1 m-0 text-sm font-medium rounded-lg w-fit bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 text-n-slate-12"
        >
          <span
            class="i-lucide-sparkles size-4 shrink-0 mt-0.5 text-n-blue-11"
            aria-hidden="true"
          />
          {{ textoNova }}
        </p>
        <p
          v-if="podeDesfazer"
          data-base-atualizada
          class="flex items-center gap-1.5 m-0 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-circle-check size-4 shrink-0 text-n-teal-11"
            aria-hidden="true"
          />
          {{ t(`${NS}.ATUALIZADA`) }}
        </p>
        <p
          v-if="podeGerenciar && erroDesfazer"
          data-base-erro-desfazer
          role="alert"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ textoErroDesfazer || t(`${NS}.DESFAZER_ERRO`) }}
        </p>
      </div>
    </div>
    <AgenteBotao
      v-if="nova"
      data-base-atualizar
      class="max-sm:w-full shrink-0"
      variante="contorno"
      @click="emit('atualizar')"
    >
      {{ t(`${NS}.ATUALIZAR`) }}
    </AgenteBotao>
    <AgenteBotao
      v-else-if="podeDesfazer"
      data-base-desfazer
      class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
      variante="fantasma"
      icone="i-lucide-undo-2"
      :carregando="desfazendo"
      :rotulo-carregando="t(`${NS}.DESFAZENDO`)"
      @click="emit('desfazer')"
    >
      {{ t(`${NS}.DESFAZER`) }}
    </AgenteBotao>
  </div>
</template>
