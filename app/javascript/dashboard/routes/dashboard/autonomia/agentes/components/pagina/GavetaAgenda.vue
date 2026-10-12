<script setup>
import { computed, onMounted, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgendaEstado from './AgendaEstado.vue';
import {
  ESTADO_AGENDA,
  SEM_PAGINA,
  useAgendaDoAgente,
} from '../../composables/useAgendaDoAgente';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import {
  ESTADO_PAGINA,
  MODO_RECEBE,
  fusoLegivel,
  liberacaoParaSalvar,
  pessoasDaPagina,
  quemRecebe,
  restricaoGravada,
} from '../../utils/agendaDaPagina';
import { idiomaDoNavegador } from '../../utils/pagina';

// #1253 — Marcar reuniões na página nova do agente: a página de agendamento que o agente usa para
// oferecer horários e marcar, ou "Não marcar". Mesma regra e mesma gravação do AgentBookingForm do
// painel antigo (`config.booking_page_id` pela action `autonomiaAgents/update`; o servidor mescla o
// config). Grava só se mudou. Quem não vê Agendamento recebe 422 do servidor: a mensagem dele vira
// o aviso e o erro da gaveta.
// #1307 — com mais de uma pessoa na página, o dono marca quem a IA pode usar
// (`config.booking_agent_ids`; todas marcadas = [] = todas). Quem ela prefere vai na instrução.
// Trocar de página volta para todas as pessoas da página nova: a liberação antiga não vale nela.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
});

const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const store = useStore();
const router = useRouter();
const { podeAbrirAgendamento } = usePermissoesDaJornada();
const NS = 'AGENTS.JORNADA.PAGINA.GAVETA_AGENDA';
const NS_ESTADO = 'AGENTS.JORNADA.PAGINA.AGENDA_ESTADO';
const campoId = `agenda-${useId()}`;
const erroPessoasId = `${campoId}-pessoas-erro`;

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
// Página salva que foi apagada, mesmo com a lista vazia: a gaveta diz que ela não existe mais e
// deixa escolher "Não marcar", em vez de só ensinar a criar uma página.
const temEscolha = computed(
  () =>
    agenda.paginas.value.length > 0 || agenda.paginaSalva.value !== SEM_PAGINA
);
const semPaginas = computed(() => agenda.disponivel.value && !temEscolha.value);
const podeEscolher = computed(
  () => agenda.disponivel.value && temEscolha.value
);
// #1181 (item A) — o que a página escolhida faz de verdade, quem fica com a reunião e o fuso, só com
// o que a lista de páginas traz (utils/agendaDaPagina). Segue a escolha da tela, antes de salvar.
const paginaEscolhida = computed(() => agenda.paginaDe(escolhida.value));
const pessoas = computed(() => pessoasDaPagina(paginaEscolhida.value));
const mostraPessoas = computed(() => pessoas.value.length > 1);
const marcadas = ref([]);
const nenhumaMarcada = computed(
  () => mostraPessoas.value && !marcadas.value.length
);
const mudouPagina = computed(
  () => escolhida.value !== agenda.paginaSalva.value
);
const todas = () => pessoas.value.map(({ id }) => id);
// O que fica marcado ao abrir e ao trocar de página: as gravadas na página salva; todas na página
// nova e na página de uma pessoa só (ali não há escolha; salvar conserta uma restrição velha).
const marcadasAoAbrir = () =>
  mudouPagina.value || !mostraPessoas.value
    ? todas()
    : agenda.liberadasDe(escolhida.value);
// Só a troca de página e a chegada da lista recomeçam a escolha: o agente atualizado com a gaveta
// aberta não apaga o que o dono marcou.
watch(
  [escolhida, () => agenda.estado.value],
  () => {
    marcadas.value = marcadasAoAbrir();
  },
  { immediate: true }
);
const marcar = (id, marcada) => {
  marcadas.value = marcada
    ? pessoas.value
        .map(p => p.id)
        .filter(i => i === id || marcadas.value.includes(i))
    : marcadas.value.filter(i => i !== id);
};
const liberacao = computed(() =>
  liberacaoParaSalvar(marcadas.value, pessoas.value)
);
// A liberação gravada desta página, como a tela a mostra: "quebrada" quando a restrição não tem
// mais ninguém da página (a IA fica sem ninguém e salvar conserta).
const gravadaNaPagina = computed(() => {
  const liberadas = agenda.liberadasDe(escolhida.value);
  const gravados = props.agente?.config?.booking_agent_ids;
  if (restricaoGravada(gravados) && !liberadas.length) return 'quebrada';
  return liberacaoParaSalvar(liberadas, pessoas.value).join();
});
const mudouPessoas = computed(
  () =>
    pessoas.value.length > 0 && liberacao.value.join() !== gravadaNaPagina.value
);
// O exemplo da dica: a primeira pessoa marcada com a agenda aberta (senão a primeira da página).
const exemplo = computed(() => {
  const marcadaAtiva = pessoas.value.find(
    ({ id, ai_status: status }) =>
      marcadas.value.includes(id) && status !== 'agenda_pausada'
  );
  return (marcadaAtiva || pessoas.value[0])?.nome || '';
});
const estado = computed(() => agenda.estadoDe(escolhida.value, marcadas.value));
const tituloEscolhida = computed(() =>
  paginaEscolhida.value ? agenda.tituloDaPagina(paginaEscolhida.value) : ''
);
const linkPaginas = computed(() =>
  podeAbrirAgendamento.value
    ? router.resolve({ name: 'settings_booking' }).href
    : ''
);
const ativa = computed(() => estado.value === ESTADO_PAGINA.ATIVA);
const textoRecebe = computed(() => {
  if (mostraPessoas.value) return '';
  const recebe = quemRecebe(paginaEscolhida.value);
  if (!recebe) return '';
  const fixo = recebe.modo === MODO_RECEBE.FIXO;
  const chave = `${fixo ? 'FIXO' : 'POR_PESSOA'}${recebe.nome ? '' : '_SEM_NOME'}`;
  return t(`${NS_ESTADO}.RECEBE.${chave}`, { nome: recebe.nome });
});
const fuso = computed(() =>
  fusoLegivel(paginaEscolhida.value?.timezone, idiomaDoNavegador(locale.value))
);
const placeholder = computed(() =>
  estado.value === ESTADO_PAGINA.NAO_EXISTE ? t(`${NS_ESTADO}.ESCOLHA`) : ''
);

// Só o que mudou. Página nova leva a liberação junto (todas = []), para a restrição de outra
// página não deixar a agenda sem ninguém.
const configParaSalvar = () => {
  if (escolhida.value === SEM_PAGINA) return { booking_page_id: null };
  if (mudouPagina.value) {
    return {
      booking_page_id: escolhida.value,
      booking_agent_ids: liberacao.value,
    };
  }
  return { booking_agent_ids: liberacao.value };
};

const salvar = async () => {
  if (salvando.value || nenhumaMarcada.value) return;
  if (!mudouPagina.value && !mudouPessoas.value) {
    emit('fechar');
    return;
  }
  erroSalvar.value = '';
  salvando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: props.agente.id,
      config: configParaSalvar(),
    });
    useAlert(t(`${NS}.PRONTO`));
    emit('fechar');
  } catch {
    // Texto fixo como nas outras gavetas: a mensagem crua ("AxiosError: ...") não diz nada a quem usa.
    erroSalvar.value = t(`${NS}.ERRO`);
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
            :placeholder="placeholder"
            :disabled="salvando"
            class="w-full"
          />
        </div>
        <div data-estado class="flex flex-col gap-2" aria-live="polite">
          <AgendaEstado
            :estado="estado"
            :nome="nome"
            :pagina="tituloEscolhida"
            :link-paginas="linkPaginas"
            gerencia
          />
          <p
            v-if="ativa && textoRecebe"
            data-recebe
            class="m-0 text-sm text-n-slate-11"
          >
            {{ textoRecebe }}
          </p>
          <p v-if="ativa && fuso" data-fuso class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS_ESTADO}.FUSO`, { fuso }) }}
          </p>
        </div>
        <fieldset
          v-if="mostraPessoas"
          data-pessoas
          class="flex flex-col gap-2 p-0 m-0 border-0 min-w-0"
          :disabled="salvando"
          :aria-describedby="nenhumaMarcada ? erroPessoasId : undefined"
        >
          <legend class="p-0 mb-1 text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.PESSOAS.TITULO`, { nome }) }}
          </legend>
          <ul class="flex flex-col gap-1 p-0 m-0 list-none">
            <li v-for="pessoa in pessoas" :key="pessoa.id">
              <label
                :data-pessoa="pessoa.id"
                class="flex items-center gap-3 px-3 min-h-11 rounded-xl cursor-pointer hover:bg-n-alpha-1"
              >
                <Checkbox
                  :model-value="marcadas.includes(pessoa.id)"
                  :disabled="salvando"
                  @update:model-value="marcada => marcar(pessoa.id, marcada)"
                />
                <span class="text-sm text-n-slate-12">{{ pessoa.nome }}</span>
                <span
                  v-if="pessoa.ai_status === 'agenda_pausada'"
                  data-pessoa-pausada
                  class="text-xs text-n-amber-11"
                >
                  {{ t(`${NS}.PESSOAS.PAUSADA`) }}
                </span>
              </label>
            </li>
          </ul>
          <p
            v-if="nenhumaMarcada"
            :id="erroPessoasId"
            data-pessoas-erro
            role="alert"
            class="m-0 text-sm text-n-ruby-11"
          >
            {{ t(`${NS}.PESSOAS.NENHUMA`) }}
          </p>
          <p data-pessoas-dica class="m-0 text-sm text-n-slate-11">
            {{
              t(`${NS}.PESSOAS.DICA`, {
                nome,
                exemplo,
              })
            }}
          </p>
        </fieldset>
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
          :desabilitado="nenhumaMarcada"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
