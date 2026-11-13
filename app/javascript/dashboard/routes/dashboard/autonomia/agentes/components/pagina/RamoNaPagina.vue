<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ProntoDoRamo from '../criar/ProntoDoRamo.vue';
import { useMudancaDasListas } from '../../composables/useMudancaDasListas';

// #2976 — na página de um agente que nasceu de um agente pronto por ramo e JÁ ATENDE: o que ele pergunta e os
// documentos que pede, nas mesmas linhas e gavetas da Confira (ProntoDoRamo). O dono tira (e põe de volta), edita e
// inclui; a mudança vale na mensagem seguinte do cliente, porque o agente lê as listas a cada resposta.
// As listas vêm no próprio agente (`listas_do_ramo`, só para quem nasceu de um modelo, com a conta podendo usá-lo e
// fora do modo manual). Sem elas o bloco não aparece. As ferramentas não entram aqui: no agente que atende elas são
// as da gaveta "Ferramentas".
// `podeMudar` falso (quem só vê): as gavetas abrem só para ler.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeMudar: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.RAMOS.PAGINA';

const listas = computed(() => props.agente.listas_do_ramo || null);

const { gravando, mudar } = useMudancaDasListas({
  gravar: mudanca =>
    store.dispatch('autonomiaAgents/mudarModeloPronto', {
      agentId: props.agente.id,
      listas: mudanca,
    }),
  pode: () => Boolean(listas.value),
  aoFalhar: () => useAlert(t('AGENTS.JORNADA.RAMOS.CONFIRA.ERRO_AO_MUDAR')),
});
</script>

<template>
  <ProntoDoRamo
    v-if="listas"
    na-pagina
    :nome="nome"
    :titulo="t(`${NS}.TITULO`, { nome })"
    :nota="podeMudar ? t(`${NS}.NOTA`, { nome }) : ''"
    :perguntas="listas.perguntas"
    :documentos="listas.documentos"
    :pode-mudar="podeMudar"
    :gravando="gravando"
    @mudar="mudar($event.lista, $event.itens, $event.aoGravar)"
  />
  <!-- Agente que não nasceu de um agente pronto por ramo: o bloco não aparece. -->
  <template v-else />
</template>
