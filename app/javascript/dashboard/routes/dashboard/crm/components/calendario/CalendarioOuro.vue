<script setup>
// Calendário Ouro — a página do calendário remodelada. Abre no "Meu dia"
// (o que fazer hoje, uma ação por linha); semana e mês são visões de apoio.
// Filtros num painel só ("Mostrar"). Dia e hora sempre no fuso da conta.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarioHeroi from './CalendarioHeroi.vue';
import CalendarioMeuDia from './CalendarioMeuDia.vue';
import CalendarioMiniMes from './CalendarioMiniMes.vue';
import CalendarioFaixaSemana from './CalendarioFaixaSemana.vue';
import CalendarioSemana from './CalendarioSemana.vue';
import CalendarioMes from './CalendarioMes.vue';
import CalendarioMostrar from './CalendarioMostrar.vue';
import CalendarioNovo from './CalendarioNovo.vue';
import CalendarioReuniao from './CalendarioReuniao.vue';
import { useJeitoDeMarcar } from '../card/useJeitoDeMarcar';
import { TIPOS } from './itensDoCalendario';
import {
  dataDaChave,
  formatarDia,
  inicioDaSemana,
  somarDias,
} from './tempoNaConta';
import { useCalendarioOuro } from './useCalendarioOuro';

const props = defineProps({
  events: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
  owners: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
  // Funil escolhido no "Mostrar"; vazio = todos os funis (decisão 2 do #1568).
  funil: { type: [String, Number], default: null },
  funis: { type: Array, default: () => [] },
  ehAdmin: { type: Boolean, default: false },
  temWhatsapp: { type: Boolean, default: false },
  reunioesLigadas: { type: Boolean, default: false },
  // Saídas para o que o topo antigo do calendário tinha (Configurar).
  podeAgendamento: { type: Boolean, default: false },
  podeCaixas: { type: Boolean, default: false },
  // Caixas da conta: dizem se há agenda do Google/Microsoft para marcar reunião.
  caixas: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'rangeChange',
  'abrir',
  'abrirConversa',
  'novo',
  'concluir',
  'proximoPasso',
  'adiarAtrasados',
  'retry',
  'update:funil',
  'abrirAgendamento',
  'abrirCaixas',
  'reuniaoMarcada',
]);

const { t, locale } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();
const fuso = computed(() => fusoDaConta(currentAccount.value));
const idioma = computed(() => locale.value.replace('_', '-'));
// Decisão 4 do #1568: administrador vê toda a equipe; agente, só os seus.
const cal = useCalendarioOuro({
  props,
  fuso,
  ehAdmin: computed(() => props.ehAdmin),
});
const { hoje, visao, dia, janela, itens, marcas } = cal;

watch(
  [janela, cal.feitos],
  ([{ de, ate }, feitos]) =>
    emit('rangeChange', {
      from: cal.instante(de, '00:00'),
      to: cal.instante(ate, '23:59'),
      includeCompleted: feitos,
    }),
  { immediate: true }
);

const mostrarAberto = ref(false);
const VISOES = [
  { id: 'dia', icone: 'i-lucide-list-checks' },
  { id: 'semana', icone: 'i-lucide-columns-3' },
  { id: 'mes', icone: 'i-lucide-calendar-days' },
];

const periodo = computed(() => {
  if (visao.value === 'mes') {
    return formatarDia(dia.value, idioma.value, {
      month: 'long',
      year: 'numeric',
    });
  }
  if (visao.value === 'semana') {
    const de = inicioDaSemana(dia.value);
    return t('CRM_CALENDARIO.NAV.SEMANA_DE', {
      de: formatarDia(de, idioma.value, { day: 'numeric', month: 'short' }),
      ate: formatarDia(somarDias(de, 6), idioma.value, {
        day: 'numeric',
        month: 'short',
      }),
    });
  }
  if (dia.value === hoje.value) return t('CRM_CALENDARIO.DIA.HOJE');
  return formatarDia(dia.value, idioma.value, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
});

const nomeDe = id => {
  if (!id || Number(id) === Number(props.currentUserId)) return '';
  return props.owners.find(o => Number(o.id) === Number(id))?.name || '';
};

const pendentesHoje = computed(
  () => itens.value.filter(i => i.chave === hoje.value && !i.feito).length
);
const atrasados = computed(
  () => itens.value.filter(i => i.atrasado && i.chave < hoje.value).length
);
const primeiroNome = computed(
  () => (store.getters.getCurrentUser?.name || '').split(' ')[0]
);

/* Concluir e o próximo passo */
const concluindo = ref([]);
const recemFeitos = ref([]);
watch(
  () => props.events,
  () => {
    concluindo.value = [];
  }
);
const esquecerFeito = item => {
  recemFeitos.value = recemFeitos.value.filter(f => f.id !== item.id);
};
// Marca na hora; se o servidor recusar, a página chama `falhou` e a linha
// volta como estava (sem "Feito", com o círculo de novo).
const concluir = item => {
  concluindo.value = [...concluindo.value, item.id];
  recemFeitos.value = [
    item,
    ...recemFeitos.value.filter(f => f.id !== item.id),
  ].slice(0, 2);
  emit('concluir', {
    evento: item.evento,
    falhou: () => {
      concluindo.value = concluindo.value.filter(id => id !== item.id);
      esquecerFeito(item);
    },
  });
};
const DIAS_DO_ATALHO = { AMANHA: 1, TRES_DIAS: 3 };
const diaDoAtalho = atalho =>
  atalho === 'SEMANA'
    ? somarDias(inicioDaSemana(hoje.value), 8)
    : somarDias(hoje.value, DIAS_DO_ATALHO[atalho]);
const proximoPasso = ({ item, atalho }) => {
  esquecerFeito(item);
  emit('proximoPasso', {
    evento: item.evento,
    titulo: item.titulo,
    quando: cal.instante(diaDoAtalho(atalho), '09:00'),
    fuso: fuso.value,
  });
};
const adiarAtrasados = lista =>
  emit('adiarAtrasados', {
    eventos: lista.map(i => i.evento),
    quando: cal.instante(somarDias(hoje.value, 1), '09:00'),
  });

const abrir = item => emit('abrir', item.evento);
const acao = ({ item, acao: escolhida }) => {
  if (escolhida.conversa) emit('abrirConversa', escolhida.conversa);
  else emit('abrir', item.evento);
};
// "Novo": lembrete, reunião e mensagem marcada, só o que a conta tem ligado.
// Só com o lembrete, vai direto para ele.
const TIPO_DO_FLUXO = {
  lembrete: 'reminder',
  mensagem: 'whatsapp',
};
const opcoesDoNovo = computed(() =>
  [
    'lembrete',
    props.reunioesLigadas && 'reuniao',
    props.temWhatsapp && 'mensagem',
  ].filter(Boolean)
);
const escolha = ref(null);
const diaDoNovo = ref(null);
// Reunião com cliente: o agendamento novo, direto na gaveta daqui, com o
// negócio escolhido em "Com quem?" e o dia escolhido no calendário. Como a
// conta marca (página, Google/Microsoft ou falta) é a mesma regra do card.
const route = useRoute();
const router = useRouter();
const jeitoDeMarcar = useJeitoDeMarcar({
  store,
  router,
  caixas: computed(() => props.caixas),
  ligado: computed(() => props.reunioesLigadas),
});
const reuniao = ref({ show: false, cardId: null, dia: '' });
const abrirFluxo = (opcao, extra = {}) => {
  if (opcao === 'reuniao') {
    reuniao.value = { show: true, cardId: extra.cardId, dia: diaDoNovo.value };
    return;
  }
  emit('novo', {
    date: dataDaChave(diaDoNovo.value),
    // #1590: o dia escolhido como chave do fuso da conta (a Mensagem marcada usa direto).
    dia: diaDoNovo.value,
    type: TIPO_DO_FLUXO[opcao],
  });
};
const novo = chave => {
  diaDoNovo.value = chave || dia.value;
  if (opcoesDoNovo.value.length === 1) abrirFluxo('lembrete');
  else escolha.value?.open();
};
const funisDoMostrar = computed(() => [
  { value: null, label: t('CRM_CALENDARIO.MOSTRAR.TODOS_FUNIS') },
  ...props.funis,
]);
const escolherDia = chave => {
  dia.value = chave;
  visao.value = 'dia';
};
</script>

<template>
  <div
    data-calendario-ouro
    class="flex min-h-0 flex-1 flex-col overflow-y-auto bg-n-background"
  >
    <CalendarioHeroi
      :hoje="hoje"
      :idioma="idioma"
      :nome="primeiroNome"
      :minutos="cal.agoraMinutos.value"
      :pendentes="pendentesHoje"
      :atrasados="atrasados"
      @novo="novo(hoje)"
    />

    <div
      class="mx-auto flex w-full max-w-[90rem] flex-col gap-5 px-4 pb-10 pt-5 sm:px-8"
    >
      <!-- Barra: visão, navegação e "Mostrar" -->
      <div class="flex flex-wrap items-center gap-3">
        <div
          class="grid w-full grid-cols-3 gap-1 rounded-xl bg-n-alpha-2 p-1 sm:w-auto"
          role="group"
          :aria-label="t('CRM_CALENDARIO.VISAO.ROTULO')"
        >
          <button
            v-for="opcao in VISOES"
            :key="opcao.id"
            type="button"
            :data-visao="opcao.id"
            :aria-pressed="visao === opcao.id"
            class="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              visao === opcao.id
                ? 'bg-n-solid-1 font-semibold text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="visao = opcao.id"
          >
            <span class="size-4" :class="opcao.icone" aria-hidden="true" />
            {{ t(`CRM_CALENDARIO.VISAO.${opcao.id.toUpperCase()}`) }}
          </button>
        </div>

        <div class="flex min-w-0 flex-1 items-center gap-1">
          <button
            type="button"
            data-nav="anterior"
            class="grid size-11 shrink-0 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('CRM_CALENDARIO.NAV.ANTERIOR')"
            @click="cal.andar(-1)"
          >
            <span
              class="i-lucide-chevron-left size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <button
            type="button"
            data-nav="seguinte"
            class="grid size-11 shrink-0 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('CRM_CALENDARIO.NAV.SEGUINTE')"
            @click="cal.andar(1)"
          >
            <span
              class="i-lucide-chevron-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <h2
            class="mb-0 min-w-0 flex-1 px-1 text-base font-semibold leading-tight text-n-slate-12 first-letter:uppercase sm:flex-none sm:text-lg"
          >
            {{ periodo }}
          </h2>
          <Button
            v-if="!cal.noPeriodoDeHoje.value"
            data-nav="hoje"
            :label="t('CRM_CALENDARIO.NAV.HOJE_CURTO')"
            :aria-label="t('CRM_CALENDARIO.NAV.VOLTAR_HOJE')"
            slate
            faded
            class="!min-h-11 shrink-0"
            @click="cal.irParaHoje"
          />
        </div>

        <button
          type="button"
          data-mostrar-abrir
          :aria-label="t('CRM_CALENDARIO.MOSTRAR.BOTAO')"
          :aria-expanded="mostrarAberto"
          class="inline-flex min-h-11 items-center gap-2 rounded-xl border px-4 text-sm font-medium transition"
          :class="
            mostrarAberto
              ? 'border-n-slate-12 bg-n-slate-12 text-n-solid-1'
              : 'border-n-weak bg-n-solid-1 text-n-slate-12 hover:border-n-slate-7'
          "
          @click="mostrarAberto = !mostrarAberto"
        >
          <span class="i-lucide-sliders-horizontal size-4" aria-hidden="true" />
          <span class="hidden sm:inline">{{
            t('CRM_CALENDARIO.MOSTRAR.BOTAO')
          }}</span>
          <span
            v-if="cal.filtrosLigados.value"
            class="grid size-5 place-items-center rounded-full bg-n-blue-9 text-xs font-semibold text-white"
          >
            {{ cal.filtrosLigados.value }}
          </span>
        </button>
      </div>

      <CalendarioMostrar
        v-if="mostrarAberto"
        v-model:quem="cal.quem.value"
        v-model:tipos="cal.tipos.value"
        v-model:feitos="cal.feitos.value"
        :tipos-disponiveis="cal.tiposDisponiveis.value"
        :funil="funil"
        :funis="funisDoMostrar"
        :pode-agendamento="podeAgendamento"
        :pode-caixas="podeCaixas"
        @update:funil="emit('update:funil', $event)"
        @abrir-agendamento="emit('abrirAgendamento')"
        @abrir-caixas="emit('abrirCaixas')"
        @fechar="mostrarAberto = false"
      />

      <!-- Erro -->
      <div
        v-if="error"
        class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-n-ruby-7 px-6 py-12 text-center"
      >
        <span
          class="i-lucide-cloud-off size-8 text-n-ruby-10"
          aria-hidden="true"
        />
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CRM_CALENDARIO.ERRO') }}
        </p>
        <Button
          :label="t('CRM_CALENDARIO.TENTAR')"
          slate
          faded
          class="!min-h-11"
          @click="emit('retry')"
        />
      </div>

      <!-- Carregando pela primeira vez -->
      <div
        v-else-if="loading && !events.length"
        class="flex flex-col gap-2"
        aria-busy="true"
      >
        <span
          v-for="n in 4"
          :key="n"
          class="h-[4.5rem] animate-pulse rounded-2xl bg-n-alpha-2"
        />
      </div>

      <!-- Meu dia -->
      <div
        v-else-if="visao === 'dia'"
        class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <div class="flex min-w-0 flex-col gap-5">
          <CalendarioFaixaSemana
            class="lg:hidden"
            :dia="dia"
            :hoje="hoje"
            :idioma="idioma"
            :marcas="marcas"
            @escolher="dia = $event"
          />
          <CalendarioMeuDia
            :itens="itens"
            :hoje="hoje"
            :dia="dia"
            :agora-minutos="cal.agoraMinutos.value"
            :agora="cal.agora.value"
            :fuso="fuso"
            :idioma="idioma"
            :nome-de="nomeDe"
            :concluindo="concluindo"
            :recem-feitos="recemFeitos"
            @concluir="concluir"
            @abrir="abrir"
            @acao="acao"
            @proximo-passo="proximoPasso"
            @esquecer-feito="esquecerFeito"
            @adiar-atrasados="adiarAtrasados"
            @novo="novo"
          />
        </div>
        <aside class="hidden flex-col gap-4 lg:sticky lg:top-4 lg:flex">
          <CalendarioMiniMes
            v-model:mes="cal.mesDoMini.value"
            :dia="dia"
            :hoje="hoje"
            :idioma="idioma"
            :marcas="marcas"
            @escolher="dia = $event"
          />
          <div
            data-legenda
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
              {{ t('CRM_CALENDARIO.LEGENDA.TITULO') }}
            </h3>
            <ul class="m-0 flex list-none flex-col gap-3 p-0">
              <li
                v-for="tipo in cal.tiposDisponiveis.value"
                :key="tipo"
                class="flex items-start gap-3"
              >
                <span
                  class="grid size-8 shrink-0 place-items-center rounded-lg"
                  :class="TIPOS[tipo].tom"
                  aria-hidden="true"
                >
                  <span class="size-4" :class="TIPOS[tipo].icone" />
                </span>
                <span class="min-w-0">
                  <span class="block text-sm font-medium text-n-slate-12">
                    {{ t(`CRM_CALENDARIO.TIPO_LONGO.${tipo.toUpperCase()}`) }}
                  </span>
                  <span class="block text-xs text-n-slate-10">
                    {{ t(`CRM_CALENDARIO.EXEMPLO.${tipo.toUpperCase()}`) }}
                  </span>
                </span>
              </li>
            </ul>
          </div>
        </aside>
      </div>

      <CalendarioSemana
        v-else-if="visao === 'semana'"
        :itens="itens"
        :dia="dia"
        :hoje="hoje"
        :fuso="fuso"
        :idioma="idioma"
        @escolher-dia="escolherDia"
        @abrir="abrir"
        @novo="novo"
      />
      <CalendarioMes
        v-else
        :itens="itens"
        :mes="dia"
        :hoje="hoje"
        :fuso="fuso"
        :idioma="idioma"
        @escolher-dia="escolherDia"
        @abrir="abrir"
      />
    </div>
    <p
      data-fuso
      class="mx-auto mb-0 flex w-full max-w-[90rem] items-center gap-2 px-4 pb-6 text-xs text-n-slate-10 sm:px-8"
    >
      <span class="i-lucide-globe size-3.5" aria-hidden="true" />
      {{ t('CRM_CALENDARIO.FUSO', { fuso: rotuloDoFuso(fuso) }) }}
    </p>
    <CalendarioNovo
      ref="escolha"
      :opcoes="opcoesDoNovo"
      :jeito-reuniao="jeitoDeMarcar.jeito.value"
      :pode-criar-pagina="jeitoDeMarcar.podeCriarPagina.value"
      @escolher="abrirFluxo"
      @criar-pagina="jeitoDeMarcar.abrirPaginas"
    />
    <CalendarioReuniao
      :show="reuniao.show"
      :card-id="reuniao.cardId"
      :dia="reuniao.dia"
      :jeito="jeitoDeMarcar.jeito.value"
      :paginas="jeitoDeMarcar.paginas.value"
      :caixas="caixas"
      :account-id="route.params.accountId"
      @marcou="emit('reuniaoMarcada', $event)"
      @close="reuniao = { ...reuniao, show: false }"
    />
  </div>
</template>
