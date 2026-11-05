<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { fraseDoPasso } from '../frases';
import { acharPasso } from '../receita';
import { linhasDoEnsaio } from '../ensaio';

// #2498 — Ensaiar: o que a automação faria nas conversas recentes que a pessoa
// enxerga, sem fazer nada. A automação salva ensaia a versão dela; com
// rascunho (ou a nova, sem id), vai a receita da tela.
const props = defineProps({
  automacaoId: { type: Number, default: null },
  receita: { type: Object, required: true },
  rascunho: { type: Boolean, default: false },
  catalogo: { type: Object, required: true },
});
const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const estado = ref('carregando');
const problemas = ref([]);
const erro = ref('');
const conversas = ref([]);
const outras = ref([]);
const escolhida = ref(null);
const extra = ref(null);

const raiz = ref(null);
const passosRef = ref(null);

const corpo = conversaId => ({
  receita: props.rascunho || !props.automacaoId ? props.receita : undefined,
  conversaId,
});

const carregar = async () => {
  estado.value = 'carregando';
  problemas.value = [];
  extra.value = null;
  try {
    const { data } = await AutomacoesAPI.ensaiar(props.automacaoId, corpo());
    conversas.value = data.conversas;
    outras.value = data.outras || [];
    escolhida.value =
      (data.conversas.find(item => item.entraria) || data.conversas[0])
        ?.conversa_id ?? null;
    estado.value = 'pronto';
  } catch (e) {
    erro.value = e.response?.data?.error || '';
    problemas.value = e.response?.data?.problemas || [];
    estado.value = 'erro';
  }
};

// Outra conversa: ensaia só ela e a põe no fim da lista.
const ensaiarOutra = async conversaId => {
  if (conversas.value.some(item => item.conversa_id === conversaId)) {
    escolhida.value = conversaId;
    return;
  }
  try {
    const { data } = await AutomacoesAPI.ensaiar(
      props.automacaoId,
      corpo(conversaId)
    );
    [extra.value] = data.conversas;
    escolhida.value = conversaId;
  } catch {
    erro.value = t('AUTOMACAO_LIVRE.ENSAIO.ERRO');
  }
};

const todas = computed(() =>
  extra.value ? [...conversas.value, extra.value] : conversas.value
);
const casaram = computed(
  () => conversas.value.filter(item => item.entraria).length
);
const atual = computed(() =>
  todas.value.find(item => item.conversa_id === escolhida.value)
);

const fraseDe = id => {
  const passo = acharPasso(props.receita.passos || [], id);
  return passo ? fraseDoPasso(passo, props.catalogo, t) : '';
};
const linhas = computed(() =>
  atual.value?.entraria ? linhasDoEnsaio(atual.value.passos, fraseDe, t) : []
);

const nomeDe = item =>
  item.nome || t('AUTOMACAO_LIVRE.ENSAIO.CONVERSA_N', { n: item.conversa_id });
const opcoes = computed(() =>
  [...conversas.value, ...outras.value].map(item => ({
    value: item.conversa_id,
    // Duas conversas do mesmo contato: o número separa uma da outra.
    label: t('AUTOMACAO_LIVRE.ENSAIO.OPCAO', {
      nome: nomeDe(item),
      n: item.conversa_id,
    }),
  }))
);

const iniciais = item =>
  nomeDe(item)
    .split(' ')
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase();

watch(escolhida, () => {
  if (window.matchMedia('(max-width: 767px)').matches)
    requestAnimationFrame(() =>
      passosRef.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    );
});

onMounted(() => {
  raiz.value?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  carregar();
});

const ICONE = {
  mensagem: 'i-lucide-message-circle',
  avisar: 'i-lucide-bell',
  esperar: 'i-lucide-hourglass',
  esperar_ate: 'i-lucide-timer',
  se: 'i-lucide-split',
  decidir: 'i-lucide-sparkles',
  extrair: 'i-lucide-sparkles',
  escrever: 'i-lucide-sparkles',
  resumir: 'i-lucide-sparkles',
  parar: 'i-lucide-octagon',
  acao: 'i-lucide-zap',
};
</script>

<template>
  <section
    ref="raiz"
    data-ensaio
    class="flex flex-col gap-5 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.TITULO')"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col gap-1">
        <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ENSAIO.TITULO') }}
        </h2>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ENSAIO.SUBTITULO') }}
        </p>
      </div>
      <Button
        data-fechar-ensaio
        :label="$t('AUTOMACAO_LIVRE.ENSAIO.FECHAR')"
        icon="i-lucide-x"
        slate
        link
        class="min-h-11"
        @click="emit('fechar')"
      />
    </div>

    <div
      v-if="estado === 'carregando'"
      data-carregando
      aria-busy="true"
      :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.CARREGANDO')"
      class="h-40 rounded-2xl bg-n-alpha-2 animate-pulse"
    />

    <div
      v-else-if="estado === 'erro'"
      data-erro
      role="alert"
      class="flex flex-col items-start gap-3"
    >
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ erro || $t('AUTOMACAO_LIVRE.ENSAIO.ERRO') }}
      </p>
      <ul
        v-if="problemas.length"
        class="flex flex-col gap-1 m-0 text-sm ps-5 text-n-ruby-11"
      >
        <li v-for="problema in problemas" :key="problema">{{ problema }}</li>
      </ul>
      <Button
        v-else
        :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="min-h-11"
        @click="carregar"
      />
    </div>

    <p
      v-else-if="!conversas.length"
      data-vazio
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('AUTOMACAO_LIVRE.ENSAIO.SEM_CONVERSAS') }}
    </p>

    <template v-else>
      <p role="status" class="flex flex-wrap items-baseline m-0 gap-x-3">
        <span
          data-casaram
          class="text-4xl font-bold tracking-tight tabular-nums text-n-teal-11"
        >
          {{ casaram }}
        </span>
        <span class="text-base text-n-slate-11">
          {{
            $t('AUTOMACAO_LIVRE.ENSAIO.QUANTAS', { total: conversas.length })
          }}
        </span>
      </p>

      <div class="grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
        <div class="flex flex-col gap-3">
          <ul
            class="flex flex-col p-0 m-0 list-none border divide-y rounded-2xl border-n-weak divide-n-weak"
          >
            <li v-for="item in todas" :key="item.conversa_id">
              <button
                type="button"
                data-ensaio-item
                :aria-pressed="item.conversa_id === escolhida"
                class="flex items-center w-full gap-3 px-3 py-2 text-start min-h-11"
                :class="
                  item.conversa_id === escolhida
                    ? 'bg-n-blue-2'
                    : 'hover:bg-n-alpha-1'
                "
                @click="escolhida = item.conversa_id"
              >
                <span
                  class="grid text-xs font-bold rounded-full place-items-center size-8 shrink-0 bg-n-slate-3 text-n-slate-11"
                  aria-hidden="true"
                >
                  {{ iniciais(item) }}
                </span>
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-[0.9375rem] truncate text-n-slate-12">
                    {{ nomeDe(item) }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ relativeTimeFromISO(item.ultima_atividade, locale) }}
                  </span>
                </span>
                <span
                  class="text-sm font-semibold shrink-0"
                  :class="item.entraria ? 'text-n-teal-11' : 'text-n-slate-10'"
                >
                  {{
                    item.entraria
                      ? $t('AUTOMACAO_LIVRE.ENSAIO.ENTRARIA')
                      : $t('AUTOMACAO_LIVRE.ENSAIO.NAO_ENTRARIA')
                  }}
                </span>
              </button>
            </li>
          </ul>
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-11">
              {{ $t('AUTOMACAO_LIVRE.ENSAIO.OUTRA') }}
            </span>
            <ChoiceSelect
              data-outra
              :model-value="escolhida"
              :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.OUTRA')"
              :placeholder="$t('AUTOMACAO_LIVRE.ENSAIO.ESCOLHA')"
              :options="opcoes"
              @update:model-value="ensaiarOutra"
            />
          </div>
        </div>

        <div
          v-if="atual"
          ref="passosRef"
          data-ensaio-passos
          class="flex flex-col gap-4 p-5 rounded-2xl bg-n-alpha-1"
        >
          <p class="mb-0 text-[0.9375rem] font-semibold text-n-slate-12">
            {{
              $t('AUTOMACAO_LIVRE.ENSAIO.NA_CONVERSA', { nome: nomeDe(atual) })
            }}
          </p>
          <p
            v-if="!atual.entraria"
            data-nao-entra
            class="mb-0 text-[0.9375rem] text-n-slate-11"
          >
            {{
              $t(`AUTOMACAO_LIVRE.ENSAIO.FORA.${atual.motivo.toUpperCase()}`)
            }}
          </p>
          <ol v-else class="flex flex-col gap-3 p-0 m-0 list-none">
            <li
              v-for="(linha, indice) in linhas"
              :key="indice"
              class="flex flex-col gap-2"
              :style="{ marginInlineStart: `${linha.nivel * 1.5}rem` }"
            >
              <span
                v-if="linha.caminho"
                data-caminho
                class="text-sm font-semibold tracking-wide uppercase text-n-slate-11"
              >
                {{ linha.texto }}
              </span>
              <template v-else>
                <span class="flex items-start gap-2.5">
                  <span
                    class="grid mt-0.5 rounded-lg place-items-center size-7 shrink-0 bg-n-solid-1 text-n-slate-11"
                    aria-hidden="true"
                  >
                    <span
                      :class="ICONE[linha.tipo] || 'i-lucide-circle-dot'"
                      class="size-4"
                    />
                  </span>
                  <span class="text-[0.9375rem] text-n-slate-12">
                    {{ linha.texto }}
                    <strong v-if="linha.destaque">{{ linha.destaque }}</strong>
                  </span>
                </span>
                <p
                  v-if="linha.aviso"
                  data-nao-sairia
                  class="mb-0 text-sm ms-9 text-n-amber-11"
                >
                  {{ linha.aviso }}
                </p>
                <div
                  v-if="linha.balao"
                  data-balao
                  class="self-start max-w-[18rem] px-4 py-2.5 ms-9 text-[0.9375rem] rounded-2xl rounded-ss-sm shadow-sm bg-n-teal-3 text-n-slate-12 whitespace-pre-line"
                >
                  {{ linha.balao }}
                </div>
              </template>
            </li>
          </ol>
        </div>
      </div>
    </template>
  </section>
</template>
