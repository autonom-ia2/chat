<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import VitrineJaVem from './VitrineJaVem.vue';
import { ferramentaPorId } from '../catalogo';
import { useVitrine } from '../useVitrine';
import { useVitrineLigada } from '../useVitrineLigada';

// #2776 J6 — o agente nasce com as ferramentas da vitrine que combinam com o que a pessoa contou. Quem escolhe é o
// modelo do Construtor, pelo sentido da conversa, e devolve os ids em `ferramentas_sugeridas` do agente (lista vazia
// = "nenhuma combina"). Nenhuma lista de palavras na tela. Só vêm aqui ferramentas da vitrine, que não pedem nada da
// pessoa: a chave é da plataforma. Elas entram já incluídas, com a frase "Use quando…" pronta; "Tirar" tira.
// No PROTÓTIPO, os ids vêm da resposta simulada do Construtor e a inclusão é o adaptador falso (useVitrine).
const props = defineProps({
  agenteId: { type: [Number, String], required: true },
  nome: { type: String, required: true },
  sugeridas: { type: Array, default: () => [] },
});

const { t } = useI18n();
const router = useRouter();
const { ligada, contaId } = useVitrineLigada();
const vitrine = useVitrine();
const tiradas = ref([]);

const ids = computed(() =>
  ligada.value
    ? props.sugeridas.filter(
        id => ferramentaPorId(id) && !tiradas.value.includes(id)
      )
    : []
);

watch(
  ids,
  lista =>
    lista.forEach(id =>
      vitrine.incluir(
        props.agenteId,
        id,
        t(`AGENTS.VITRINE.FERRAMENTAS.${id}.USE_QUANDO`)
      )
    ),
  { immediate: true }
);

const tirar = id => {
  tiradas.value = [...tiradas.value, id];
  vitrine.tirar(props.agenteId, id);
  useAlert(
    t('AGENTS.VITRINE.JA_VEM.TIRADA', {
      ferramenta: t(`AGENTS.VITRINE.FERRAMENTAS.${id}.NOME`),
    })
  );
};

const verMais = () =>
  router.push({
    name: 'autonomia_agents_vitrine',
    params: { accountId: contaId.value },
    query: { agente: props.agenteId },
  });
</script>

<template>
  <VitrineJaVem :nome="nome" :ids="ids" @tirar="tirar" @ver-mais="verMais" />
</template>
