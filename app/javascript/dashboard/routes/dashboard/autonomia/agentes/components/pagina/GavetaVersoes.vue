<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import DialogoAcao from './DialogoAcao.vue';
import { chaveDoMotivo, idiomaDoNavegador } from '../../utils/pagina';

// #1181 PR3 (protótipo T13, DECISOES.md item 6) — "Jeitos anteriores de responder": só o que a API
// tem — data, hora e uma frase pelo motivo (atualizado pelo que sabe, escrito por você, voltou a um
// jeito anterior). Sem selo "Em uso". Quem gerencia pode voltar a um jeito, com confirmação.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.PAGINA.VERSOES';

const estado = ref('carregando');
const versoes = ref([]);
const escolhida = ref(null);
const dialogo = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    versoes.value = await store.dispatch(
      'autonomiaAgents/getInstructionVersions',
      { agentId: props.agente.id }
    );
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

const idioma = computed(() => idiomaDoNavegador(locale.value));
const dataDe = versao =>
  new Date(versao.created_at).toLocaleDateString(idioma.value, {
    day: 'numeric',
    month: 'short',
  });
const horaDe = versao =>
  new Date(versao.created_at).toLocaleTimeString(idioma.value, {
    hour: '2-digit',
    minute: '2-digit',
  });
const motivoDe = versao => {
  const chave = chaveDoMotivo(versao.reason);
  return chave ? t(`${NS}.MOTIVO.${chave}`) : '';
};

const pedirVolta = versao => {
  escolhida.value = versao;
  dialogo.value?.abrir();
};

const voltar = async () => {
  await store.dispatch('autonomiaAgents/restoreInstructionVersion', {
    agentId: props.agente.id,
    versionId: escolhida.value.id,
  });
  versoes.value = store.getters['autonomiaAgents/getInstructionVersions'];
  useAlert(t(`${NS}.PRONTO`));
};
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <div v-if="estado === 'carregando'" class="flex justify-center py-6">
      <p role="status" class="sr-only">{{ t(`${NS}.CARREGANDO`) }}</p>
      <Spinner :size="24" aria-hidden="true" />
    </div>
    <AgenteErro
      v-else-if="estado === 'erro'"
      data-erro-ler
      :titulo="t(`${NS}.LER_ERRO`)"
      :garantia="t(`${NS}.LER_ERRO_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="carregar"
    />
    <div
      v-else-if="!versoes.length"
      data-vazio
      class="flex flex-col items-center gap-2 p-6 text-sm text-center rounded-2xl bg-n-slate-2 text-n-slate-11"
    >
      <span class="i-lucide-history size-8" aria-hidden="true" />
      <p class="m-0">{{ t(`${NS}.VAZIO`) }}</p>
    </div>
    <ul
      v-else
      :aria-label="t(`${NS}.LISTA`)"
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <li
        v-for="versao in versoes"
        :key="versao.id"
        data-versao
        class="flex flex-wrap items-center gap-3 p-3 rounded-xl ring-1 ring-inset ring-n-weak"
      >
        <span :id="`versao-${versao.id}`" class="flex flex-col gap-0.5 grow">
          <span class="text-sm font-semibold tabular-nums text-n-slate-12">
            {{ `${dataDe(versao)}, ${horaDe(versao)}` }}
          </span>
          <span v-if="motivoDe(versao)" class="text-sm text-n-slate-11">
            {{ motivoDe(versao) }}
          </span>
        </span>
        <AgenteBotao
          v-if="podeGerenciar"
          data-voltar
          variante="contorno"
          :aria-describedby="`versao-${versao.id}`"
          @click="pedirVolta(versao)"
        >
          {{ t(`${NS}.VOLTAR_ESTA`) }}
        </AgenteBotao>
      </li>
    </ul>

    <DialogoAcao
      ref="dialogo"
      :titulo="
        t(`${NS}.CONFIRMAR_TITULO`, {
          data: escolhida ? dataDe(escolhida) : '',
        })
      "
      :texto="t(`${NS}.CONFIRMAR_TEXTO`, { nome })"
      :confirmar="t(`${NS}.CONFIRMAR`)"
      :rotulo-carregando="t(`${NS}.VOLTANDO`)"
      :erro-titulo="t(`${NS}.ERRO`)"
      :erro-garantia="t(`${NS}.ERRO_GARANTIA`)"
      :executar="voltar"
      @fechada="escolhida = null"
    />
  </AgenteGaveta>
</template>
