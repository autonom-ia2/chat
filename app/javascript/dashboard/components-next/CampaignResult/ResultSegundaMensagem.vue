<script setup>
// #3101 — o "Mandar de novo" no resultado da primeira campanha: quando a segunda mensagem sai, ou para quem saiu e
// quantos a receberam e responderam (a mesma régua do resultado), com o caminho para o resultado da campanha nova.
// Também diz quando ela não saiu (não precisou, foi cancelada ou deu problema) e, nesses dois últimos, o caminho para
// criar outra campanha.
//
// `segunda`: { status, dias, quem, previsto_em (epoch ou nulo), campanha }
//   campanha: nula ou { channel, id, name, processing, receberam, responderam } (só no enviado)
import { computed } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { quandoFalado, useFusoDaConta } from './quandoNaConta';

const props = defineProps({
  segunda: { type: Object, required: true },
});

const NS = 'REENVIO_HORARIO.RESULTADO';
const { t, locale } = useI18n();
const fuso = useFusoDaConta();
// A mesma regra da rota de criar (administrator ou campaign_manage).
const podeCriar = usePermissionGranted('campaign_manage');
const inteiro = numero =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(numero ?? 0);

const ICONES = {
  aguardando: 'i-lucide-clock',
  enviado: 'i-lucide-send',
  sem_ninguem: 'i-lucide-users',
  cancelado: 'i-lucide-ban',
  falhou: 'i-lucide-triangle-alert',
};
const NAO_SAIU = ['cancelado', 'falhou'];

const status = computed(() => props.segunda.status);
const campanha = computed(() => props.segunda.campanha);
const icone = computed(() => ICONES[status.value] || 'i-lucide-send');
const numeros = computed(
  () => status.value === 'enviado' && Boolean(campanha.value)
);

const quem = computed(() =>
  t(
    `REENVIO_HORARIO.REENVIO.QUEM_RESUMO.${String(props.segunda.quem || 'nao_respondeu').toUpperCase()}`
  )
);

const aguardando = () => {
  const { previsto_em: previsto, dias } = props.segunda;
  if (!previsto)
    return t(`${NS}.AGUARDANDO_SEM_DATA`, { dias, quem: quem.value }, dias);
  const quando = quandoFalado(previsto, {
    fuso: fuso.value,
    locale: locale.value,
    t,
  });
  return t(`${NS}.AGUARDANDO_DATA`, { quando, quem: quem.value });
};

// A frase dos outros estados; no enviado com a campanha, a frase com os números em destaque fica no template.
const frase = computed(() => {
  switch (status.value) {
    case 'aguardando':
      return aguardando();
    case 'enviado':
      return t(`${NS}.APAGADA`);
    case 'sem_ninguem':
      return t(`${NS}.SEM_NINGUEM`);
    case 'cancelado':
      return t(`${NS}.CANCELADO`);
    case 'falhou':
      return t(`${NS}.FALHOU`);
    default:
      return '';
  }
});

const recebeu = computed(() => {
  const n = campanha.value?.receberam ?? 0;
  return t(`${NS}.RECEBERAM`, { n: inteiro(n) }, n);
});
const respondeu = computed(() => {
  const n = campanha.value?.responderam ?? 0;
  return t(`${NS}.RESPONDERAM`, { n: inteiro(n) }, n);
});

const verResultado = computed(() =>
  numeros.value
    ? {
        name: 'campaigns_journey_result',
        params: {
          channel: campanha.value.channel,
          campaignId: String(campanha.value.id),
        },
      }
    : null
);
const criar = computed(
  () => NAO_SAIU.includes(status.value) && podeCriar.value
);

const LINK =
  'flex items-center justify-center gap-1 px-3 text-sm font-medium border min-h-11 rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
</script>

<template>
  <section
    class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 border rounded-2xl border-n-weak bg-n-solid-1"
    :data-segunda-mensagem="status"
  >
    <div class="flex items-start min-w-0 gap-3">
      <span
        class="mt-0.5 size-5 shrink-0"
        :class="[
          icone,
          status === 'falhou' ? 'text-n-ruby-11' : 'text-n-slate-11',
        ]"
        aria-hidden="true"
      />
      <div class="flex flex-col min-w-0 gap-1">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.TITULO`) }}
        </h2>
        <I18nT
          v-if="numeros"
          :keypath="`${NS}.ENVIADA`"
          tag="p"
          scope="global"
          class="m-0 text-sm break-words text-n-slate-12"
          data-frase
        >
          <template #quem>{{ quem }}</template>
          <template #receberam>
            <strong class="font-semibold tabular-nums" data-receberam>
              {{ recebeu }}
            </strong>
          </template>
          <template #responderam>
            <strong class="font-semibold tabular-nums" data-responderam>
              {{ respondeu }}
            </strong>
          </template>
        </I18nT>
        <p v-else class="m-0 text-sm break-words text-n-slate-12" data-frase>
          {{ frase }}
        </p>
        <p
          v-if="numeros && campanha.processing"
          class="m-0 text-sm text-n-slate-11"
          data-saindo
        >
          {{ t(`${NS}.SAINDO`) }}
        </p>
      </div>
    </div>
    <router-link
      v-if="verResultado"
      :to="verResultado"
      :class="LINK"
      :aria-label="t(`${NS}.VER_DE`, { nome: campanha.name })"
      :title="campanha.name"
      data-ver-segunda
    >
      {{ t(`${NS}.VER`) }}
      <span class="i-lucide-arrow-right size-4 shrink-0" aria-hidden="true" />
    </router-link>
    <router-link
      v-else-if="criar"
      :to="{ name: 'campaigns_journey_new' }"
      :class="LINK"
      data-criar-campanha
    >
      {{ t(`${NS}.CRIAR`) }}
      <span class="i-lucide-plus size-4 shrink-0" aria-hidden="true" />
    </router-link>
  </section>
</template>
