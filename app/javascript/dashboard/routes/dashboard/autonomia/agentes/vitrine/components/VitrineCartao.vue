<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dataDaBase } from '../../utils/baseDoAgente';

// #2776 — o cartão de uma ferramenta pronta: o que ela faz em uma frase, o apoio ("tabela FIPE") só como detalhe, e
// um selo: o agente escolhido já sabe, quantas perguntas responde ou quando o arquivo foi atualizado. O cartão
// inteiro é o botão que abre o detalhe.
const props = defineProps({
  ferramenta: { type: Object, required: true },
  tom: { type: String, default: 'azul' },
  // Nome do agente escolhido que já tem esta ferramenta; vazio quando não tem.
  jaSabe: { type: String, default: '' },
  destaque: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const NS = 'AGENTS.VITRINE';
const { t, locale } = useI18n();

const textos = computed(() => {
  const base = `${NS}.FERRAMENTAS.${props.ferramenta.id}`;
  return {
    nome: t(`${base}.NOME`),
    apoio: t(`${base}.APOIO`),
    faz: t(`${base}.FAZ`),
  };
});

const TONS = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  rosa: 'bg-n-ruby-3 text-n-ruby-11',
  violeta: 'bg-n-iris-3 text-n-iris-11',
  cinza: 'bg-n-slate-3 text-n-slate-11',
};

const selo = computed(() => {
  if (props.jaSabe) {
    return {
      texto: t(`${NS}.CARTAO.JA_SABE`, { nome: props.jaSabe }),
      icone: 'i-lucide-check',
      classe: 'bg-n-teal-3 text-n-teal-11',
    };
  }
  if (props.ferramenta.arquivo) {
    return {
      texto: t(`${NS}.CARTAO.ATUALIZADO`, {
        data: dataDaBase(props.ferramenta.atualizadoEm, locale.value),
      }),
      icone: 'i-lucide-refresh-cw',
      classe: 'bg-n-alpha-2 text-n-slate-11',
    };
  }
  if (props.ferramenta.consultas) {
    return {
      texto: t(`${NS}.CARTAO.CONSULTAS`, { n: props.ferramenta.consultas }),
      icone: 'i-lucide-messages-square',
      classe: 'bg-n-alpha-2 text-n-slate-11',
    };
  }
  return null;
});
</script>

<template>
  <button
    type="button"
    :data-vitrine-cartao="ferramenta.id"
    class="flex flex-col h-full gap-3 p-5 text-start transition shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset hover:-translate-y-0.5 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
    :class="destaque ? 'ring-n-blue-6' : 'ring-n-weak hover:ring-n-blue-6'"
    @click="emit('abrir', ferramenta)"
  >
    <span class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-11 shrink-0"
        :class="TONS[tom] || TONS.azul"
      >
        <span :class="ferramenta.icone" class="size-6" />
      </span>
      <span class="flex flex-col min-w-0 gap-0.5">
        <span class="text-base font-semibold leading-snug text-n-slate-12">
          {{ textos.nome }}
        </span>
        <span v-if="textos.apoio" class="text-xs text-n-slate-11">
          {{ textos.apoio }}
        </span>
      </span>
    </span>
    <span class="flex-1 text-sm leading-relaxed text-n-slate-11">
      {{ textos.faz }}
    </span>
    <span
      v-if="selo"
      class="inline-flex items-center self-start gap-1.5 px-2.5 py-1 text-xs font-medium rounded-lg"
      :class="selo.classe"
    >
      <span :class="selo.icone" class="size-3.5" aria-hidden="true" />
      {{ selo.texto }}
    </span>
  </button>
</template>
