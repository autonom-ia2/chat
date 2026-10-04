<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { avisarContaMudou } from './contaMudou';
import { motivoUtilizavel } from 'dashboard/store/modules/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';

// #936 — o cartão de uma tarefa longa do Guia ("arruma os 512 nomes"). Um
// cartão por estado, cada um com UMA ação principal: a amostra (Começar), a
// pausa de segurança depois dos primeiros 25 (Seguir), o andamento (Pausar) e
// o relatório (Desfazer tudo). O cartão busca a tarefa no servidor pelo id, e
// por isso continua igual ao fechar e reabrir o Guia.
const props = defineProps({
  tarefaId: {
    type: Number,
    required: true,
  },
  // A tarefa já carregada (lista "Feito pelo Guia"): poupa a primeira busca.
  inicial: {
    type: Object,
    default: null,
  },
});

const { t, te, locale } = useI18n();

const ANDANDO = ['na_fila', 'rodando', 'desfazendo'];
const RELATORIO = ['concluida', 'cancelada', 'falhou', 'desfeita'];
const INTERVALO = 3000;

const tarefa = ref(props.inicial);
const carregando = ref(!props.inicial);
const falhouAoCarregar = ref(false);
const enviando = ref('');
const erro = ref('');
let relogio = null;
let desmontado = false;

const status = computed(() => tarefa.value?.status);
const amostra = computed(() => tarefa.value?.amostra || []);
const andando = computed(() => ANDANDO.includes(status.value));
const porcentagem = computed(() => {
  const total = tarefa.value?.total || 0;
  if (!total) return 0;
  const feitos =
    (tarefa.value.feitos || 0) +
    (tarefa.value.falhas || 0) +
    (tarefa.value.pulados || 0);
  return Math.min(100, Math.round((feitos / total) * 100));
});
const processados = computed(
  () =>
    (tarefa.value?.feitos || 0) +
    (tarefa.value?.falhas || 0) +
    (tarefa.value?.pulados || 0)
);

const quando = iso =>
  new Intl.DateTimeFormat(locale.value.replaceAll('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(iso));

const dinheiro = valor =>
  new Intl.NumberFormat(locale.value.replaceAll('_', '-'), {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(Math.max(valor, 0.01));

const custo = computed(() => {
  const valor = tarefa.value?.custo_estimado || 0;
  return valor > 0
    ? t('AUTONOMIA_GUIDE.TASK.COST', { valor: dinheiro(valor) })
    : t('AUTONOMIA_GUIDE.TASK.NO_COST');
});

const tempo = computed(() => {
  const minutos = Math.ceil((tarefa.value?.tempo_estimado || 0) / 60);
  return minutos <= 1
    ? t('AUTONOMIA_GUIDE.TASK.TIME_SHORT')
    : t('AUTONOMIA_GUIDE.TASK.TIME', { minutos });
});

// O nome de uma tabela ou de um motivo na língua da pessoa; o que não tem
// tradução aparece como veio, para nada sumir.
const traduzido = (grupo, chave) => {
  const caminho = `AUTONOMIA_GUIDE.TASK.${grupo}.${chave}`;
  return te(caminho) ? t(caminho) : chave;
};

const tabelas = computed(() =>
  Object.entries(tarefa.value?.canario?.tabelas || {})
);
const jobs = computed(() =>
  Object.values(tarefa.value?.canario?.jobs || {}).reduce((a, b) => a + b, 0)
);
const naoFeitos = computed(() => tarefa.value?.nao_feitos || []);
const desfazer = computed(() => tarefa.value?.desfazer || null);

const parar = () => {
  if (relogio) clearTimeout(relogio);
  relogio = null;
};

const buscar = async () => {
  try {
    const { data } = await AutonomiaGuideAPI.tarefa(props.tarefaId);
    if (desmontado) return;
    tarefa.value = data;
    falhouAoCarregar.value = false;
  } catch {
    if (!tarefa.value) falhouAoCarregar.value = true;
  } finally {
    carregando.value = false;
  }
  parar();
  if (!desmontado && andando.value) relogio = setTimeout(buscar, INTERVALO);
};

const tentarDeNovo = () => {
  carregando.value = true;
  falhouAoCarregar.value = false;
  buscar();
};

const comandar = async comando => {
  if (enviando.value) return;
  enviando.value = comando;
  erro.value = '';
  try {
    const { data } = await AutonomiaGuideAPI.comandarTarefa(
      props.tarefaId,
      comando
    );
    tarefa.value = data;
    if (comando === 'desfazer') avisarContaMudou();
    parar();
    if (andando.value) relogio = setTimeout(buscar, INTERVALO);
  } catch (error) {
    erro.value =
      motivoUtilizavel(error?.response?.data?.error) ||
      t('AUTONOMIA_GUIDE.TASK.ACTION_FAILED');
  } finally {
    enviando.value = '';
  }
};

onMounted(() => {
  if (!props.inicial || andando.value) buscar();
});

onBeforeUnmount(() => {
  desmontado = true;
  parar();
});
</script>

<template>
  <div
    class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2"
    data-tarefa
  >
    <p
      v-if="carregando && !tarefa"
      class="flex items-center gap-2 mb-0 text-sm text-n-slate-11"
      role="status"
    >
      <span class="i-svg-spinner size-4 shrink-0" aria-hidden="true" />
      {{ $t('AUTONOMIA_GUIDE.TASK.LOADING') }}
    </p>

    <div
      v-else-if="falhouAoCarregar && !tarefa"
      class="flex flex-col gap-2"
      role="alert"
    >
      <p class="mb-0 text-sm text-n-ruby-11">
        {{ $t('AUTONOMIA_GUIDE.TASK.LOAD_FAILED') }}
      </p>
      <Button
        :label="$t('AUTONOMIA_GUIDE.TASK.RETRY')"
        icon="i-lucide-refresh-cw"
        class="min-h-11 self-start"
        slate
        faded
        @click="tentarDeNovo"
      />
    </div>

    <template v-else-if="status === 'amostra_pronta'">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ $t('AUTONOMIA_GUIDE.TASK.SAMPLE_TITLE') }}
      </p>
      <p class="mb-0 text-sm text-n-slate-12 break-words">
        {{
          $t('AUTONOMIA_GUIDE.TASK.SAMPLE_WHAT', {
            descricao: tarefa.descricao,
            total: tarefa.total,
          })
        }}
      </p>
      <p v-if="!amostra.length" class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTONOMIA_GUIDE.TASK.SAMPLE_EMPTY') }}
      </p>
      <ul v-else class="flex flex-col gap-1 m-0 p-0 list-none">
        <li
          v-for="(par, indice) in amostra"
          :key="indice"
          class="rounded-lg bg-n-alpha-1 p-3 text-sm break-words"
        >
          <template v-if="par.pulado">
            <span class="text-n-slate-12">{{ par.ref }}</span>
            <span class="block text-n-amber-11">
              {{
                $t('AUTONOMIA_GUIDE.TASK.SAMPLE_SKIPPED', {
                  motivo: traduzido('SKIP', par.pulado),
                })
              }}
            </span>
          </template>
          <template v-else>
            <span class="block text-n-slate-11 line-through">
              <span class="sr-only">{{
                $t('AUTONOMIA_GUIDE.TASK.BEFORE')
              }}</span>
              {{ Object.values(par.antes || {}).join(' · ') }}
            </span>
            <span
              class="i-lucide-arrow-down size-4 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="block text-n-slate-12 font-medium">
              <span class="sr-only">{{
                $t('AUTONOMIA_GUIDE.TASK.AFTER')
              }}</span>
              {{ Object.values(par.depois || {}).join(' · ') }}
            </span>
          </template>
        </li>
      </ul>
      <p class="mb-0 text-xs text-n-slate-11">{{ custo }} · {{ tempo }}</p>
      <p v-if="tarefa.jev_estimado" class="mb-0 text-xs text-n-slate-11">
        {{
          $t('AUTONOMIA_GUIDE.TASK.JEV', {
            usa: tarefa.jev_estimado,
            restam: tarefa.jev_restante,
          })
        }}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.START')"
          :is-loading="enviando === 'comecar'"
          icon="i-lucide-play"
          class="min-h-11"
          blue
          @click="comandar('comecar')"
        />
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.NOT_NOW')"
          :is-loading="enviando === 'cancelar'"
          class="min-h-11"
          slate
          faded
          @click="comandar('cancelar')"
        />
      </div>
    </template>

    <template v-else-if="status === 'aguardando_ok_canario'">
      <Banner color="amber">
        {{
          $t('AUTONOMIA_GUIDE.TASK.CHECK_TITLE', {
            n: tarefa.canario?.itens || processados,
          })
        }}
      </Banner>
      <p class="mb-0 text-sm text-n-slate-12">
        {{ $t('AUTONOMIA_GUIDE.TASK.CHECK_WHAT') }}
      </p>
      <ul class="flex flex-col gap-1 m-0 p-0 list-none text-sm tabular-nums">
        <li v-for="[tabela, quantos] in tabelas" :key="tabela">
          {{
            $t('AUTONOMIA_GUIDE.TASK.CHECK_TABLE', {
              n: quantos,
              nome: traduzido('TABLES', tabela),
            })
          }}
        </li>
        <li v-if="!tabelas.length" class="text-n-slate-11">
          {{ $t('AUTONOMIA_GUIDE.TASK.CHECK_NOTHING') }}
        </li>
        <li class="text-n-slate-11">
          {{ $t('AUTONOMIA_GUIDE.TASK.CHECK_JOBS', { n: jobs }) }}
        </li>
      </ul>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.CONTINUE')"
          :is-loading="enviando === 'seguir'"
          icon="i-lucide-play"
          class="min-h-11"
          blue
          @click="comandar('seguir')"
        />
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.CANCEL')"
          :is-loading="enviando === 'cancelar'"
          class="min-h-11"
          slate
          faded
          @click="comandar('cancelar')"
        />
      </div>
    </template>

    <template v-else-if="status === 'na_fila' || status === 'rodando'">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ tarefa.descricao }}
      </p>
      <p
        class="mb-0 text-sm font-medium tabular-nums text-n-slate-12"
        role="status"
        aria-live="polite"
      >
        {{
          status === 'na_fila'
            ? $t('AUTONOMIA_GUIDE.TASK.QUEUED')
            : $t('AUTONOMIA_GUIDE.TASK.PROGRESS', {
                feitos: processados,
                total: tarefa.total,
              })
        }}
      </p>
      <div
        class="w-full h-2 overflow-hidden rounded-full bg-n-alpha-2"
        role="progressbar"
        :aria-valuenow="porcentagem"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-label="$t('AUTONOMIA_GUIDE.TASK.PROGRESS_LABEL')"
      >
        <div
          class="h-full rounded-full bg-n-brand transition-all"
          :style="{ width: `${porcentagem}%` }"
        />
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.PAUSE')"
          :is-loading="enviando === 'pausar'"
          icon="i-lucide-pause"
          class="min-h-11"
          slate
          faded
          @click="comandar('pausar')"
        />
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.CANCEL')"
          :is-loading="enviando === 'cancelar'"
          class="min-h-11"
          ruby
          ghost
          @click="comandar('cancelar')"
        />
      </div>
    </template>

    <template v-else-if="status === 'pausada'">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ tarefa.descricao }}
      </p>
      <p class="mb-0 text-sm text-n-amber-11">
        {{
          $t('AUTONOMIA_GUIDE.TASK.PAUSED', {
            feitos: processados,
            total: tarefa.total,
          })
        }}
        {{ tarefa.motivo }}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.RESUME')"
          :is-loading="enviando === 'retomar'"
          icon="i-lucide-play"
          class="min-h-11"
          blue
          @click="comandar('retomar')"
        />
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.CANCEL')"
          :is-loading="enviando === 'cancelar'"
          class="min-h-11"
          slate
          faded
          @click="comandar('cancelar')"
        />
      </div>
    </template>

    <template v-else-if="status === 'desfazendo'">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ tarefa.descricao }}
      </p>
      <p class="mb-0 text-sm text-n-slate-12 tabular-nums" role="status">
        {{
          $t('AUTONOMIA_GUIDE.TASK.UNDOING', {
            feitos: desfazer?.lotes_desfeitos || 0,
            total: desfazer?.lotes || tarefa.lotes,
          })
        }}
      </p>
    </template>

    <p
      v-else-if="status === 'cancelada' && !tarefa.lotes"
      class="mb-0 text-sm text-n-slate-11"
    >
      {{ $t('AUTONOMIA_GUIDE.TASK.CANCELED_BEFORE') }}
    </p>

    <template v-else-if="RELATORIO.includes(status)">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ $t(`AUTONOMIA_GUIDE.TASK.REPORT_TITLE.${status}`) }}
      </p>
      <p class="mb-0 text-sm text-n-slate-12 break-words">
        {{ tarefa.descricao }}
      </p>
      <p v-if="tarefa.motivo" class="mb-0 text-sm text-n-amber-11">
        {{ tarefa.motivo }}
      </p>
      <ul class="flex flex-col gap-1 mb-0 list-none p-0 text-sm tabular-nums">
        <li class="flex items-start gap-2 text-n-slate-12">
          <span
            class="i-lucide-check size-4 shrink-0 mt-1 text-n-teal-11"
            aria-hidden="true"
          />
          {{
            $t('AUTONOMIA_GUIDE.TASK.DONE_COUNT', {
              n: tarefa.feitos,
              total: tarefa.total,
            })
          }}
        </li>
        <li
          v-for="linha in naoFeitos"
          :key="`${linha.status}-${linha.motivo}`"
          class="flex items-start gap-2 break-words"
          :class="
            linha.status === 'falhou' ? 'text-n-ruby-11' : 'text-n-amber-11'
          "
        >
          <span class="i-lucide-x size-4 shrink-0 mt-1" aria-hidden="true" />
          <span>
            <span class="sr-only">
              {{ $t('AUTONOMIA_GUIDE.DONE.STEP_FAILED') }}
            </span>
            {{
              $t(`AUTONOMIA_GUIDE.TASK.NOT_DONE.${linha.status}`, {
                n: linha.total,
                motivo: traduzido('SKIP', linha.motivo || ''),
              })
            }}
          </span>
        </li>
      </ul>
      <template v-if="status === 'desfeita' && desfazer">
        <p class="mb-0 text-sm font-medium text-n-teal-11">
          {{ $t('AUTONOMIA_GUIDE.TASK.UNDONE', { n: desfazer.desfeitas }) }}
        </p>
        <p v-if="desfazer.conflitos_total" class="mb-0 text-sm text-n-amber-11">
          {{
            $t('AUTONOMIA_GUIDE.DONE.CONFLICTS', {
              count: desfazer.conflitos_total,
            })
          }}
        </p>
      </template>
      <div v-if="tarefa.desfazivel" class="flex flex-wrap items-center gap-2">
        <Button
          :label="$t('AUTONOMIA_GUIDE.TASK.UNDO_ALL')"
          :is-loading="enviando === 'desfazer'"
          icon="i-lucide-undo-2"
          class="min-h-11"
          slate
          faded
          @click="comandar('desfazer')"
        />
        <span v-if="tarefa.desfazer_ate" class="text-xs text-n-slate-11">
          {{
            $t('AUTONOMIA_GUIDE.DONE.UNTIL', {
              quando: quando(tarefa.desfazer_ate),
            })
          }}
        </span>
      </div>
    </template>

    <p v-if="erro" class="mb-0 text-sm text-n-ruby-11" role="alert">
      {{ erro }}
    </p>
  </div>
</template>
