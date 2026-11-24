<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GuideRevisaoMotivos from './GuideRevisaoMotivos.vue';

// #3158 (B8b) — o cartão da revisão de conversas em lote: o andamento
// enquanto lê e, no fim, os motivos agrupados. Busca a revisão pelo id, então
// continua igual ao fechar e reabrir o Guia. Para parar, a pessoa escreve no
// Guia (#3143): o cartão não tem botão Parar. Acima de 300, oferece ler as
// que faltam.
const props = defineProps({
  revisaoId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();

const ANDANDO = ['na_fila', 'rodando'];
const INTERVALO = 3000;

const revisao = ref(null);
const carregando = ref(true);
const falhouAoCarregar = ref(false);
const continuando = ref(false);
const erro = ref('');
let relogio = null;
let desmontado = false;

const status = computed(() => revisao.value?.status);
const andando = computed(() => ANDANDO.includes(status.value));
const progresso = computed(() => {
  const { lidas = 0, falhas = 0, limite = 0 } = revisao.value || {};
  return limite
    ? Math.min(100, Math.round(((lidas + falhas) / limite) * 100))
    : 0;
});

const diaMes = iso => {
  const [, mes, dia] = String(iso || '').split('-');
  return dia && mes ? `${dia}/${mes}` : '';
};

const cabecalho = computed(() =>
  t('AUTONOMIA_GUIDE.REVISAO.CABECALHO', {
    titulo: revisao.value.titulo,
    de: diaMes(revisao.value.de),
    ate: diaMes(revisao.value.ate),
  })
);

// Uma linha por desfecho, com a cor e o ícone do desfecho. `lidos` conta
// também as que não abriram: é até onde a revisão chegou.
const ATENCAO = { cor: 'text-n-amber-11', icone: 'i-lucide-circle-alert' };
const desfecho = computed(() => {
  const r = revisao.value;
  const n = {
    lidas: r.lidas,
    lidos: r.lidas + r.falhas,
    limite: r.limite,
    total: r.total,
  };
  if (status.value === 'parada')
    return {
      texto: t('AUTONOMIA_GUIDE.REVISAO.DESFECHO.PARADA', n),
      cor: 'text-n-amber-11',
      icone: 'i-lucide-circle-pause',
    };
  if (status.value === 'falhou')
    return {
      texto:
        r.motivo === 'sem_chave'
          ? t('AUTONOMIA_GUIDE.REVISAO.DESFECHO.SEM_CHAVE')
          : t('AUTONOMIA_GUIDE.REVISAO.DESFECHO.FALHOU'),
      cor: 'text-n-ruby-11',
      icone: 'i-lucide-circle-x',
    };
  if (r.faltam > 0)
    return {
      texto: t('AUTONOMIA_GUIDE.REVISAO.DESFECHO.NO_MAXIMO', n),
      ...ATENCAO,
    };
  const texto = t('AUTONOMIA_GUIDE.REVISAO.DESFECHO.CONCLUIDA', n);
  if (r.falhas > 0) return { texto, ...ATENCAO };
  return { texto, cor: 'text-n-teal-11', icone: 'i-lucide-circle-check' };
});

const categorias = computed(() => revisao.value?.categorias || []);

// A frase de quem terminou: o que mais pesou, em até três motivos, cada um
// em negrito. Com conversas que não abriram, diz quantas.
const NOMES_DA_CONCLUSAO = ['primeiro', 'segundo', 'terceiro'];
const conclusao = computed(() => {
  const r = revisao.value;
  if (status.value !== 'concluida' || r.faltam > 0) return null;
  if (r.falhas > 0) return { parcial: true };
  const nomes = categorias.value
    .filter(c => !c.outros)
    .map(c => c.nome)
    .slice(0, 3);
  if (!nomes.length) return null;
  const chave = [
    'AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_UM',
    'AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_DOIS',
    'AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_TRES',
  ][nomes.length - 1];
  return {
    chave,
    nomes: NOMES_DA_CONCLUSAO.slice(0, nomes.length).map((slot, i) => ({
      slot,
      nome: nomes[i],
    })),
  };
});

const parar = () => {
  if (relogio) clearTimeout(relogio);
  relogio = null;
};

const buscar = async () => {
  try {
    const { data } = await AutonomiaGuideAPI.revisao(props.revisaoId);
    if (desmontado) return;
    revisao.value = data;
    falhouAoCarregar.value = false;
  } catch {
    if (!revisao.value) falhouAoCarregar.value = true;
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

const continuar = async () => {
  if (continuando.value) return;
  continuando.value = true;
  erro.value = '';
  try {
    const { data } = await AutonomiaGuideAPI.continuarRevisao(props.revisaoId);
    revisao.value = data;
    parar();
    relogio = setTimeout(buscar, INTERVALO);
  } catch {
    erro.value = t('AUTONOMIA_GUIDE.REVISAO.CONTINUAR_FALHOU');
  } finally {
    continuando.value = false;
  }
};

onMounted(buscar);
onBeforeUnmount(() => {
  desmontado = true;
  parar();
});
</script>

<template>
  <div class="flex flex-col gap-3" data-revisao>
    <div
      class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2"
    >
      <p
        v-if="carregando"
        class="flex items-center gap-2 mb-0 text-sm text-n-slate-11"
        role="status"
      >
        <Spinner :size="16" class="shrink-0" />
        {{ t('AUTONOMIA_GUIDE.REVISAO.CARREGANDO') }}
      </p>
      <template v-else-if="falhouAoCarregar">
        <p class="mb-0 text-sm text-n-ruby-11">
          {{ t('AUTONOMIA_GUIDE.REVISAO.NAO_CARREGOU') }}
        </p>
        <Button
          sm
          slate
          faded
          class="min-h-11 self-start"
          :label="t('AUTONOMIA_GUIDE.REVISAO.TENTAR_DE_NOVO')"
          @click="tentarDeNovo"
        />
      </template>
      <template v-else-if="revisao">
        <p class="mb-0 text-xs text-n-slate-11 break-words">{{ cabecalho }}</p>
        <template v-if="andando">
          <p
            class="flex items-center gap-2 mb-0 text-sm text-n-slate-12"
            role="status"
          >
            <Spinner :size="16" class="shrink-0 text-n-brand" />
            {{
              t('AUTONOMIA_GUIDE.REVISAO.LENDO', {
                lidas: revisao.lidas + revisao.falhas,
                limite: revisao.limite,
              })
            }}
          </p>
          <div
            class="h-1.5 w-full rounded-full bg-n-alpha-2"
            role="progressbar"
            :aria-valuenow="progresso"
            aria-valuemin="0"
            aria-valuemax="100"
            :aria-label="t('AUTONOMIA_GUIDE.REVISAO.PROGRESSO')"
          >
            <div
              class="h-1.5 rounded-full bg-n-brand"
              :style="{ width: `${progresso}%` }"
            />
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('AUTONOMIA_GUIDE.REVISAO.PODE_FECHAR') }}
          </p>
        </template>
        <p
          v-else
          class="flex items-center gap-2 mb-0 text-sm font-medium"
          :class="desfecho.cor"
          role="status"
        >
          <span
            class="size-4 shrink-0"
            :class="desfecho.icone"
            aria-hidden="true"
          />
          {{ desfecho.texto }}
        </p>
      </template>
    </div>

    <template v-if="revisao && !andando">
      <p v-if="conclusao?.parcial" class="mb-0 text-sm text-n-slate-12">
        {{
          t('AUTONOMIA_GUIDE.REVISAO.CONCLUSAO_PARCIAL', {
            lidas: revisao.lidas,
            falhas: revisao.falhas,
          })
        }}
      </p>
      <I18nT
        v-else-if="conclusao"
        :keypath="conclusao.chave"
        tag="p"
        scope="global"
        class="mb-0 text-sm text-n-slate-12"
      >
        <template v-for="item in conclusao.nomes" :key="item.slot" #[item.slot]>
          <strong class="font-semibold">{{ item.nome }}</strong>
        </template>
      </I18nT>
      <template v-if="revisao.faltam > 0 && status !== 'falhou'">
        <p class="mb-0 text-sm text-n-slate-12">
          {{
            t('AUTONOMIA_GUIDE.REVISAO.FALTAM_PERGUNTA', {
              lidas: revisao.lidas + revisao.falhas,
              total: revisao.total,
              faltam: revisao.faltam,
            })
          }}
        </p>
        <Button
          class="min-h-11 self-start"
          icon="i-lucide-play"
          :label="
            t('AUTONOMIA_GUIDE.REVISAO.LER_FALTAM', {
              faltam: Math.min(revisao.faltam, 300),
            })
          "
          :is-loading="continuando"
          @click="continuar"
        />
        <p v-if="erro" class="mb-0 text-sm text-n-ruby-11" role="alert">
          {{ erro }}
        </p>
      </template>
      <GuideRevisaoMotivos v-if="categorias.length" :revisao="revisao" />
    </template>
  </div>
</template>
