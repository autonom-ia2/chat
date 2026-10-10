<script setup>
import { onBeforeUnmount, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import TesteDoAgente from './TesteDoAgente.vue';
import { useTesteDoAgente } from '../../composables/useTesteDoAgente';

// #1181 PR3 (protótipo T08) — gaveta Testar: "Ninguém recebe estas mensagens", a faixa âmbar quando
// o agente está parado e o celular de teste. A pergunta escrita no bloco Testar da página chega em
// `pergunta` e já vai. "Respondeu errado?" leva ao Mudar conversando com a pergunta e a resposta.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  atendendo: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  pergunta: { type: String, default: '' },
});

const emit = defineEmits(['fechar', 'errado']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.TESTE';
const teste = useTesteDoAgente(toRef(props, 'agente'));
const celular = ref(null);

onMounted(() => {
  if (props.pergunta) teste.enviar(props.pergunta);
  else celular.value?.focar();
});

onBeforeUnmount(() => teste.parar());
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`, { nome })" @fechar="emit('fechar')">
    <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.NINGUEM`) }}</p>
    <p
      v-if="!atendendo"
      data-parado
      class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.PARADO`, { nome }) }}
    </p>
    <TesteDoAgente
      ref="celular"
      :teste="teste"
      :nome="nome"
      :tipo="agente.agent_type"
      :pode-mudar="podeMudar"
      @errado="emit('errado', $event)"
    />
  </AgenteGaveta>
</template>
