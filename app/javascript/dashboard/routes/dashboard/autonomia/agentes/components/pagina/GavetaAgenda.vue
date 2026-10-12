<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import BookingChoiceCards from 'dashboard/routes/dashboard/settings/booking/components/BookingChoiceCards.vue';
import BookingStatusBadge from 'dashboard/routes/dashboard/settings/booking/components/BookingStatusBadge.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgendaPessoas from './AgendaPessoas.vue';
import AgendaExemplo from './AgendaExemplo.vue';
import {
  ESTADO_AGENDA,
  SEM_PAGINA,
  idDaPagina,
  useAgendaDoAgente,
} from '../../composables/useAgendaDoAgente';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import {
  ESTADO_PAGINA,
  MODO_RECEBE,
  liberacaoParaSalvar,
  pessoasDaPagina,
  quemRecebe,
  restricaoGravada,
  tiposDeLocal,
  ehRascunho,
} from '../../utils/agendaDaPagina';
import { GAVETA } from '../../utils/pagina';

// #1253 — Marcar reuniões na página nova do agente: a página de agendamento que o agente usa para
// oferecer horários e marcar, ou "Não marcar". Mesma regra e mesma gravação do AgentBookingForm do
// painel antigo (`config.booking_page_id` pela action `autonomiaAgents/update`; o servidor mescla o
// config). Grava só se mudou.
// #1307 — com mais de uma pessoa na página, o dono marca quem a IA pode usar
// (`config.booking_agent_ids`; todas marcadas = [] = todas). Quem ela prefere vai na instrução.
// Trocar de página volta para todas as pessoas da página nova: a liberação antiga não vale nela.
// #1370 — mesmo modelo mental de CRM › Agendamento › Páginas e links: um cartão por página (título,
// selo No ar/Pausada/Rascunho, locais, duração quando a lista trouxer e reuniões marcadas), com
// "Não marcar reuniões" primeiro; as pessoas com foto e "Todas as pessoas"; um exemplo de como o
// cliente vê; e "Criar uma página" leva ao assistente de lá (a gaveta não duplica o assistente).
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeMudar: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'mudar']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();
const { podeAbrirAgendamento } = usePermissoesDaJornada();
const podeGerenciarAgendamento = useCanManage('agendamento_manage');
const NS = 'AGENTS.JORNADA.PAGINA.GAVETA_AGENDA';
const NS_ESTADO = 'AGENTS.JORNADA.PAGINA.AGENDA_ESTADO';

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
const estado = computed(() => agenda.estadoDe(escolhida.value, marcadas.value));
const tituloEscolhida = computed(() =>
  paginaEscolhida.value ? agenda.tituloDaPagina(paginaEscolhida.value) : ''
);
const ativa = computed(() => estado.value === ESTADO_PAGINA.ATIVA);
// Aviso só quando a escolha pede atenção: a página ativa e "Não marcar" falam pelo próprio cartão.
const aviso = computed(
  () => ![ESTADO_PAGINA.NENHUMA, ESTADO_PAGINA.ATIVA].includes(estado.value)
);
const COM_LINK = [
  ESTADO_PAGINA.PAUSADA,
  ESTADO_PAGINA.SEM_NINGUEM,
  ESTADO_PAGINA.AGENDA_PAUSADA,
];
const CHAVE_DO_AVISO = {
  [ESTADO_PAGINA.NAO_EXISTE]: 'NAO_EXISTE',
  [ESTADO_PAGINA.PAUSADA]: 'PAUSADA',
  [ESTADO_PAGINA.SEM_NINGUEM]: 'SEM_NINGUEM',
  [ESTADO_PAGINA.AGENDA_PAUSADA]: 'AGENDA_PAUSADA',
};
const textoDoAviso = computed(() =>
  t(`${NS_ESTADO}.${CHAVE_DO_AVISO[estado.value]}`, {
    nome: props.nome,
    pagina: tituloEscolhida.value,
  })
);
const hrefPaginas = computed(() =>
  podeAbrirAgendamento.value
    ? router.resolve({ name: 'settings_booking' }).href
    : ''
);
const linkPaginas = computed(() =>
  COM_LINK.includes(estado.value) ? hrefPaginas.value : ''
);
// #1371 — o assistente de CRM › Agendamento abre vazio com `nova=1` e volta com `voltar`: a página
// do agente com `?gaveta=agenda`, que reabre esta gaveta (AgentePage tira a consulta ao abrir).
const podeCriarPagina = computed(
  () => podeAbrirAgendamento.value && podeGerenciarAgendamento.value
);
const rotaCriar = computed(() => ({
  name: 'settings_booking',
  params: { accountId: route.params.accountId },
  query: { nova: 1, voltar: `${route.path}?gaveta=${GAVETA.AGENDA}` },
}));
const hrefCriar = computed(() => router.resolve(rotaCriar.value).href);
const criarPagina = () => router.push(rotaCriar.value);

// Quem fica com a reunião numa página de uma pessoa só: a foto e o nome dela.
const pessoaUnica = computed(() =>
  pessoas.value.length === 1 ? pessoas.value[0] : null
);
const textoRecebe = computed(() => {
  if (mostraPessoas.value) return '';
  const recebe = quemRecebe(paginaEscolhida.value);
  if (!recebe) return '';
  const fixo = recebe.modo === MODO_RECEBE.FIXO;
  const nomeRecebe = recebe.nome || pessoaUnica.value?.nome || '';
  const chave = `${fixo ? 'FIXO' : 'POR_PESSOA'}${nomeRecebe ? '' : '_SEM_NOME'}`;
  return t(`${NS_ESTADO}.RECEBE.${chave}`, { nome: nomeRecebe });
});

// Os cartões: "Não marcar reuniões" e um por página, com as linhas do cartão de Páginas e links.
const nomeDoLocal = tipo => t(`BOOKING.WHERE.${tipo.toUpperCase()}.NAME`);
const linhasDaPagina = pagina => {
  const locais = tiposDeLocal(pagina).map(nomeDoLocal).join(', ');
  const reunioes = pagina.upcoming_meetings_count || 0;
  return [
    locais && { icone: 'i-lucide-map-pin', texto: locais },
    pagina.duration_minutes && {
      icone: 'i-lucide-clock',
      texto: t(`${NS}.CARTAO.DURACAO`, { minutos: pagina.duration_minutes }),
    },
    {
      icone: 'i-lucide-calendar-check',
      texto: t('BOOKING.CARD.UPCOMING', reunioes),
    },
  ].filter(Boolean);
};
const cartoes = computed(() => [
  {
    value: SEM_PAGINA,
    label: t(`${NS}.CARTAO.NAO_MARCAR`),
    linhas: [
      {
        icone: 'i-lucide-calendar-off',
        texto: t(`${NS_ESTADO}.NENHUMA`, { nome: props.nome }),
      },
    ],
  },
  ...agenda.paginas.value
    .filter(pagina => !ehRascunho(pagina))
    .map(pagina => ({
      value: idDaPagina(pagina.id),
      label: agenda.tituloDaPagina(pagina),
      pagina,
      linhas: linhasDaPagina(pagina),
    })),
]);
// Rascunho não é escolha (decisão do Rodrigo, #1370): cartão apagado, fora do grupo de rádios, com o
// que falta para publicar nas palavras do assistente (BOOKING.PREVIEW.MISSING) e o link das páginas.
// A página pausada continua escolha: o dono pode retomá-la, e o aviso âmbar explica.
const FALTAS = ['host', 'location', 'working_hours', 'pipeline'];
const rascunhos = computed(() =>
  agenda.paginas.value.filter(ehRascunho).map(pagina => ({
    id: idDaPagina(pagina.id),
    titulo: agenda.tituloDaPagina(pagina),
    pagina,
    faltas: pagina.missing
      .filter(falta => FALTAS.includes(falta))
      .map(falta => t(`BOOKING.PREVIEW.MISSING.${falta.toUpperCase()}`)),
  }))
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
      <p class="m-0 text-base text-n-slate-11">
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

      <!-- Conta sem página: um convite, com uma ação só (o assistente de Páginas e links). -->
      <div
        v-else-if="semPaginas"
        data-sem-paginas
        class="flex flex-col items-center gap-4 px-6 py-10 text-center rounded-2xl bg-n-alpha-1"
      >
        <span
          class="grid rounded-full place-items-center size-16 bg-n-blue-3"
          aria-hidden="true"
        >
          <span class="i-lucide-calendar-plus size-8 text-n-blue-11" />
        </span>
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${NS}.SEM_PAGINAS.TITULO`) }}
        </h3>
        <p class="max-w-sm m-0 text-base text-n-slate-11">
          {{ t(`${NS}.SEM_PAGINAS.TEXTO`, { nome }) }}
        </p>
        <AgenteBotao
          v-if="podeCriarPagina"
          data-criar-pagina
          tamanho="lg"
          icone="i-lucide-plus"
          @click="criarPagina"
        >
          {{ t(`${NS}.CRIAR`) }}
        </AgenteBotao>
        <p v-else data-peca-pagina class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.SEM_PAGINAS.PECA`) }}
        </p>
      </div>

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

        <fieldset
          data-escolha
          class="flex flex-col gap-3 p-0 m-0 border-0 min-w-0"
          :disabled="salvando"
        >
          <BookingChoiceCards
            v-model="escolhida"
            :legend="t(`${NS}.QUAL_PAGINA`, { nome })"
            :options="cartoes"
          >
            <template #option="{ option }">
              <span class="flex items-start justify-between gap-2">
                <span
                  class="min-w-0 text-base font-semibold break-words text-n-slate-12"
                >
                  {{ option.label }}
                </span>
                <BookingStatusBadge
                  v-if="option.pagina"
                  :page="option.pagina"
                  class="shrink-0"
                />
              </span>
              <span
                v-for="linha in option.linhas"
                :key="linha.icone"
                class="flex items-start gap-1.5 text-sm text-n-slate-11"
              >
                <span
                  class="size-4 mt-0.5 shrink-0"
                  :class="linha.icone"
                  aria-hidden="true"
                />
                {{ linha.texto }}
              </span>
            </template>
          </BookingChoiceCards>
          <ul
            v-if="rascunhos.length"
            data-rascunhos
            class="grid gap-3 p-0 m-0 list-none grid-cols-[repeat(auto-fit,minmax(min(100%,13rem),1fr))]"
          >
            <li
              v-for="rascunho in rascunhos"
              :key="rascunho.id"
              :data-rascunho="rascunho.id"
              aria-disabled="true"
              class="flex flex-col gap-1 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-alpha-1"
            >
              <span class="flex items-start justify-between gap-2">
                <span
                  class="min-w-0 text-base font-semibold break-words text-n-slate-11"
                >
                  {{ rascunho.titulo }}
                </span>
                <BookingStatusBadge :page="rascunho.pagina" class="shrink-0" />
              </span>
              <span class="text-sm text-n-slate-12">
                {{ t(`${NS}.RASCUNHO.DICA`, { nome }) }}
              </span>
              <span
                v-if="rascunho.faltas.length"
                data-faltas
                class="flex flex-col gap-0.5 text-sm text-n-slate-11"
              >
                <span>{{ t('BOOKING.PREVIEW.MISSING_TITLE') }}</span>
                <span
                  v-for="falta in rascunho.faltas"
                  :key="falta"
                  class="flex items-start gap-1.5"
                >
                  <span
                    class="i-lucide-circle-dashed size-4 mt-0.5 shrink-0"
                    aria-hidden="true"
                  />
                  {{ falta }}
                </span>
              </span>
              <a
                v-if="hrefPaginas"
                data-abrir-rascunho
                :href="hrefPaginas"
                target="_blank"
                rel="noopener noreferrer"
                class="relative inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              >
                {{ t(`${NS_ESTADO}.ABRIR_PAGINAS`) }}
                <span
                  class="i-lucide-external-link size-4"
                  aria-hidden="true"
                />
                <span class="sr-only">{{
                  t('AGENTS.JORNADA.COMUM.NOVA_ABA')
                }}</span>
              </a>
            </li>
          </ul>
          <a
            v-if="podeCriarPagina"
            data-criar-pagina
            :href="hrefCriar"
            class="inline-flex items-center gap-1.5 text-sm font-semibold min-h-11 w-fit text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click.prevent="criarPagina"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ t(`${NS}.CRIAR`) }}
          </a>
        </fieldset>

        <div
          v-if="aviso"
          :data-estado-agenda="estado"
          role="status"
          class="flex flex-col gap-2 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
        >
          <p class="flex items-start gap-2 m-0 text-base text-n-slate-12">
            <span
              class="i-lucide-triangle-alert size-5 mt-0.5 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            <span>{{ textoDoAviso }}</span>
          </p>
          <a
            v-if="linkPaginas"
            data-abrir-paginas
            :href="linkPaginas"
            target="_blank"
            rel="noopener noreferrer"
            class="relative inline-flex items-center gap-1 text-sm font-semibold underline ms-7 min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          >
            {{ t(`${NS_ESTADO}.ABRIR_PAGINAS`) }}
            <span class="i-lucide-external-link size-4" aria-hidden="true" />
            <span class="sr-only">{{
              t('AGENTS.JORNADA.COMUM.NOVA_ABA')
            }}</span>
          </a>
        </div>

        <!-- Uma pessoa só: quem fica com a reunião, com a foto. -->
        <div
          v-if="paginaEscolhida && !mostraPessoas && textoRecebe && !aviso"
          data-recebe
          class="flex items-center gap-3 p-4 rounded-2xl bg-n-alpha-1"
        >
          <Avatar
            v-if="pessoaUnica"
            :name="pessoaUnica.nome"
            :size="36"
            rounded-full
          />
          <p class="m-0 text-base text-n-slate-12">{{ textoRecebe }}</p>
        </div>

        <div v-if="mostraPessoas" class="flex flex-col gap-2">
          <AgendaPessoas
            v-model:marcadas="marcadas"
            :pessoas="pessoas"
            :nome="nome"
            :desabilitado="salvando"
          />
          <I18nT
            data-pessoas-dica
            :keypath="`${NS}.PESSOAS.DICA`"
            tag="p"
            scope="global"
            class="m-0 text-sm text-n-slate-11"
          >
            <template #nome>{{ nome }}</template>
            <template #acao>
              <button
                v-if="podeMudar"
                data-ir-mudar
                type="button"
                class="relative inline p-0 font-semibold align-baseline rounded text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 after:absolute after:inset-x-0 after:-inset-y-3"
                @click="emit('mudar')"
              >
                {{ t(`${NS}.PESSOAS.DICA_ACAO`) }}
              </button>
              <b v-else class="font-semibold text-n-slate-12">{{
                t(`${NS}.PESSOAS.DICA_ACAO`)
              }}</b>
            </template>
          </I18nT>
        </div>

        <AgendaExemplo v-if="ativa" :nome="nome" :pagina="tituloEscolhida" />
      </template>
    </div>
    <template v-if="podeEscolher" #rodape>
      <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
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
