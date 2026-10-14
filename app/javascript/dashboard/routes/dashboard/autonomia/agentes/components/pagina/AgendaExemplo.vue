<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CelularConversa from '../CelularConversa.vue';

// #1370 — "Como o cliente vê": um balão de EXEMPLO de como o agente oferece horários, com o selo
// "Exemplo" no celular e a frase dizendo que o agente escreve com as próprias palavras. Os dias do
// exemplo são fictícios (não são os horários livres de agora, que mudam a cada minuto) e o texto
// não cita o fuso (#1363).
const props = defineProps({
  nome: { type: String, required: true },
  pagina: { type: String, required: true },
});

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.GAVETA_AGENDA.EXEMPLO';

const mensagens = computed(() => [
  { de: 'cliente', texto: t(`${NS}.CLIENTE`) },
  { de: 'agente', texto: t(`${NS}.AGENTE`, { pagina: props.pagina }) },
]);
</script>

<template>
  <section data-exemplo class="flex flex-col gap-3">
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.TITULO`) }}
    </h3>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.TEXTO`, { nome }) }}
    </p>
    <div class="p-4 rounded-2xl bg-n-alpha-1">
      <CelularConversa
        tamanho="mini"
        :selo="t(`${NS}.SELO`)"
        :rotulo-sr="t(`${NS}.SR`, { nome })"
        :mensagens="mensagens"
      />
    </div>
    <p data-exemplo-nota class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.NOTA`, { nome }) }}
    </p>
  </section>
</template>
