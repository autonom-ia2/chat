<script setup>
import { computed, onBeforeUnmount, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import TesteDoAgente from './TesteDoAgente.vue';
import { useTesteDoAgente } from '../../composables/useTesteDoAgente';
import { ehCotacao, MAX_FOTO } from '../../utils/pagina';

// #1181 PR3 (protótipo T08) — gaveta Testar: "Ninguém recebe estas mensagens", a faixa âmbar quando
// o agente está parado e o celular de teste. A pergunta escrita no bloco Testar da página chega em
// `pergunta` e já vai. "Respondeu errado?" leva ao Mudar conversando com a pergunta e a resposta.
// #1427 — na Fase 2 o celular ganha o clipe: foto para todos (lida só neste teste), arquivo só para quem gerencia
// ("Quer que aprenda com isto?"). A cotação (a Lia) fica sem clipe; fora da Fase 2, como na main.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  atendendo: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  pergunta: { type: String, default: '' },
  fase2: { type: Boolean, default: false },
  podeGerenciar: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'errado', 'verSabe']);

const { t } = useI18n();
const clipe = computed(() => {
  if (!props.fase2 || ehCotacao(props.agente)) return '';
  return props.podeGerenciar ? 'tudo' : 'fotos';
});
const teste = useTesteDoAgente(
  toRef(props, 'agente'),
  clipe.value
    ? {
        textoSoFoto: t('AGENTS.JORNADA.CRIAR.CONFIRA.FOTO'),
        tetoDaFoto: MAX_FOTO,
      }
    : {}
);
const celular = ref(null);

onMounted(() => {
  if (props.pergunta) teste.enviar(props.pergunta);
  else celular.value?.focar();
});

onBeforeUnmount(() => teste.parar());
</script>

<template>
  <AgenteGaveta
    :titulo="t('AGENTS.JORNADA.PAGINA.TESTE.TITULO', { nome })"
    @fechar="emit('fechar')"
  >
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.JORNADA.PAGINA.TESTE.NINGUEM') }}
    </p>
    <p
      v-if="!atendendo"
      data-parado
      class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t('AGENTS.JORNADA.PAGINA.TESTE.PARADO', { nome }) }}
    </p>
    <TesteDoAgente
      ref="celular"
      :teste="teste"
      :nome="nome"
      :tipo="agente.agent_type"
      :pode-mudar="podeMudar"
      :clipe="clipe"
      :agente-id="agente.id"
      @errado="emit('errado', $event)"
      @ver-sabe="emit('verSabe')"
    />
  </AgenteGaveta>
</template>
