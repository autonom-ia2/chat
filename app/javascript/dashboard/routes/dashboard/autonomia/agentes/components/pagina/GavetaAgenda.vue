<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import {
  ESTADO_AGENDA,
  SEM_PAGINA,
  useAgendaDoAgente,
} from '../../composables/useAgendaDoAgente';

// #1253 — Marcar reuniões na página nova do agente: a página de agendamento que o agente usa para
// oferecer horários e marcar, ou "Não marcar". Mesma regra e mesma gravação do AgentBookingForm do
// painel antigo (`config.booking_page_id` pela action `autonomiaAgents/update`; o servidor mescla o
// config). Grava só se mudou. Quem não vê Agendamento recebe 422 do servidor: a mensagem dele vira
// o aviso e o erro da gaveta.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.PAGINA.GAVETA_AGENDA';
const campoId = `agenda-${useId()}`;

const agenda = useAgendaDoAgente(() => props.agente);
const escolhida = ref(agenda.paginaSalva.value);
const salvando = ref(false);
const erroSalvar = ref('');

const carregando = computed(
  () => agenda.estado.value === ESTADO_AGENDA.CARREGANDO
);
const erroLer = computed(
  () => agenda.estado.value === ESTADO_AGENDA.INDISPONIVEL
);
const semPaginas = computed(
  () => agenda.disponivel.value && !agenda.paginas.value.length
);
const podeEscolher = computed(
  () => agenda.disponivel.value && agenda.paginas.value.length > 0
);
const pausada = computed(
  () => agenda.paginaDe(escolhida.value)?.enabled === false
);

const salvar = async () => {
  if (salvando.value) return;
  if (escolhida.value === agenda.paginaSalva.value) {
    emit('fechar');
    return;
  }
  erroSalvar.value = '';
  salvando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: props.agente.id,
      config: {
        booking_page_id:
          escolhida.value === SEM_PAGINA ? null : escolhida.value,
      },
    });
    useAlert(t(`${NS}.PRONTO`));
    emit('fechar');
  } catch (erro) {
    erroSalvar.value = erro?.message || t(`${NS}.ERRO`);
  } finally {
    salvando.value = false;
  }
};

onMounted(agenda.carregar);
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <div class="flex flex-col gap-6" :aria-busy="salvando ? 'true' : undefined">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.TEXTO`, { nome }) }}
      </p>

      <p
        v-if="carregando"
        data-carregando
        role="status"
        class="flex items-center gap-2 p-4 m-0 text-sm rounded-2xl bg-n-slate-2 text-n-slate-11"
      >
        <span
          class="i-lucide-loader-circle size-4 shrink-0 motion-safe:animate-spin"
          aria-hidden="true"
        />
        {{ t(`${NS}.CARREGANDO`) }}
      </p>

      <AgenteErro
        v-else-if="erroLer"
        data-erro-ler
        :titulo="t(`${NS}.ERRO_LER`)"
        :garantia="t(`${NS}.GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="agenda.carregar"
      />

      <p
        v-else-if="semPaginas"
        data-sem-paginas
        class="m-0 text-sm text-n-slate-12"
      >
        {{ t('BOOKING.AI_AGENT.EMPTY') }}
      </p>

      <template v-else-if="podeEscolher">
        <AgenteErro
          v-if="erroSalvar"
          data-erro
          :titulo="erroSalvar"
          :garantia="t(`${NS}.GARANTIA`)"
          :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
          :carregando="salvando"
          @acao="salvar"
        />
        <div class="flex flex-col gap-1">
          <label :for="campoId" class="text-sm font-medium text-n-slate-12">
            {{ t('BOOKING.AI_AGENT.PAGE_LABEL') }}
          </label>
          <ChoiceSelect
            v-model="escolhida"
            data-escolha
            :trigger-id="campoId"
            :options="agenda.opcoes.value"
            :aria-label="t('BOOKING.AI_AGENT.PAGE_LABEL')"
            :disabled="salvando"
            class="w-full"
          />
          <p v-if="pausada" data-pausada class="m-0 text-sm text-n-amber-11">
            {{ t('BOOKING.AI_AGENT.PAUSED_HINT') }}
          </p>
        </div>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('BOOKING.AI_AGENT.HINT') }}
        </p>
      </template>
    </div>
    <template v-if="podeEscolher" #rodape>
      <div class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="salvando"
          @click="emit('fechar')"
        >
          {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          data-salvar
          tamanho="lg"
          :carregando="salvando"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
