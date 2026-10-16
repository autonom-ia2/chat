<script setup>
import { computed } from 'vue';
import { aoTeclarNoGrupo } from '../helpers/setas';
import { chaveDoModo, useIaDeAssunto } from '../helpers/iaDeAssunto';

// #1149 — etapa 3: o que o sistema faz sozinho quando chega mensagem. Com
// vários funis, o card nasce quando o assunto é identificado (R9/R17); com um
// funil só, pode nascer assim que a conversa chega, como hoje. A opção marcada
// mostra um exemplo do que acontece.
const props = defineProps({
  umFunil: { type: Boolean, required: true },
  // Para o exemplo: nome do primeiro funil, etapa inicial e próxima pessoa.
  funil: { type: String, default: '' },
  etapa: { type: String, default: '' },
  pessoa: { type: String, default: '' },
  // Funis marcados com a IA desligada: a IA de assunto não os reconhece.
  funisSemIa: { type: Array, default: () => [] },
});

const modo = defineModel('modo', { type: String, required: true });

const opcoes = computed(() =>
  props.umFunil ? ['chegou', 'off'] : ['auto', 'suggest', 'off']
);

// #1676 — com a IA de assunto na caixa de 1 funil, os textos de 1 funil mudam.
const iaDeAssunto = useIaDeAssunto();
const chave = opcao => chaveDoModo(opcao, props.umFunil, iaDeAssunto.value);
// O que o sistema faz com a opção, não o valor gravado: 'off' de 1 funil com a
// IA de assunto entende o assunto como o 'auto' de vários.
const entendeAssunto = opcao =>
  ['AUTO', 'AUTO_UM', 'SUGGEST'].includes(chave(opcao));
const usaIaDoFunil = opcao =>
  ['AUTO', 'AUTO_UM', 'SUGGEST', 'CHEGOU_IA'].includes(chave(opcao));
</script>

<template>
  <div
    class="flex flex-col gap-3"
    role="radiogroup"
    :aria-label="$t('CRM_CAIXAS.ETAPAS.SOZINHO')"
    @keydown="aoTeclarNoGrupo($event, opcoes, modo, valor => (modo = valor))"
  >
    <div
      v-for="opcao in opcoes"
      :key="opcao"
      class="rounded-2xl border-2 bg-n-solid-1 transition-colors"
      :class="modo === opcao ? 'border-n-blue-9' : 'border-n-weak'"
    >
      <button
        type="button"
        role="radio"
        :aria-checked="modo === opcao"
        :tabindex="modo === opcao ? 0 : -1"
        :data-modo="opcao"
        class="flex min-h-11 w-full items-start gap-4 p-4 text-start"
        @click="modo = opcao"
      >
        <span
          class="mt-0.5 grid size-6 shrink-0 place-items-center rounded-full border-2"
          :class="modo === opcao ? 'border-n-blue-9' : 'border-n-slate-7'"
          aria-hidden="true"
        >
          <span v-if="modo === opcao" class="size-3 rounded-full bg-n-blue-9" />
        </span>
        <span class="flex flex-col gap-1">
          <span class="text-base font-semibold text-n-slate-12">
            {{ $t(`CRM_CAIXAS.SOZINHO.${chave(opcao)}`) }}
            <span
              v-if="opcao === opcoes[0]"
              class="ms-1 rounded-md bg-n-teal-3 px-1.5 py-0.5 text-xs font-medium text-n-teal-11"
            >
              {{ $t('CRM_CAIXAS.SOZINHO.RECOMENDADO') }}
            </span>
          </span>
          <span class="text-[0.9375rem] text-n-slate-11">
            {{ $t(`CRM_CAIXAS.SOZINHO.${chave(opcao)}_TEXTO`) }}
          </span>
        </span>
      </button>

      <div
        v-if="modo === opcao"
        data-exemplo
        class="mx-4 mb-4 flex flex-col gap-3 rounded-xl bg-n-alpha-2 p-4"
      >
        <span class="text-sm font-medium text-n-slate-11">
          {{ $t('CRM_CAIXAS.SOZINHO.EXEMPLO') }}
        </span>
        <p
          class="mb-0 max-w-xs self-start rounded-2xl rounded-tl-md bg-n-solid-1 px-4 py-2.5 text-[0.9375rem] text-n-slate-12 shadow-sm"
        >
          {{ $t('CRM_CAIXAS.SOZINHO.MENSAGEM') }}
        </p>
        <p class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-12">
          <span
            class="mt-0.5 size-4 shrink-0"
            :class="
              chave(opcao) === 'OFF'
                ? 'i-lucide-hand'
                : 'i-lucide-sparkles text-n-blue-11'
            "
            aria-hidden="true"
          />
          {{
            $t(`CRM_CAIXAS.SOZINHO.${chave(opcao)}_EXEMPLO`, {
              funil,
              etapa,
              pessoa,
            })
          }}
        </p>
        <p v-if="entendeAssunto(opcao)" class="mb-0 text-sm text-n-slate-11">
          {{ $t('CRM_CAIXAS.SOZINHO.NAO_ENTENDEU') }}
        </p>
        <p
          v-if="usaIaDoFunil(opcao) && funisSemIa.length"
          data-sem-ia
          role="status"
          class="mb-0 flex items-start gap-2 rounded-lg bg-n-amber-3 px-3 py-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{
            $t('CRM_CAIXAS.SOZINHO.SEM_IA', { funis: funisSemIa.join(', ') })
          }}
        </p>
      </div>
    </div>
  </div>
</template>
