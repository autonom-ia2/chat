<script setup>
// #3101 — o "Mandar de novo" no resultado da primeira campanha: quando a segunda mensagem sai, ou quantos a receberam e
// responderam (a mesma régua do resultado), com o caminho para o resultado da campanha nova ("<nome> · segunda
// mensagem"). Também diz quando ela não saiu: não sobrou ninguém, foi cancelada ou deu problema.
//
// `segunda`: { status, dias, quem, previsto_em (epoch ou nulo), campanha }
//   campanha: nula ou { channel, id, name, processing, receberam, responderam } (só no enviado)
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { quandoFalado, useFusoDaConta } from './quandoNaConta';

const props = defineProps({
  segunda: { type: Object, required: true },
});

const NS = 'REENVIO_HORARIO.RESULTADO';
const { t, locale } = useI18n();
const fuso = useFusoDaConta();
const inteiro = numero =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(numero ?? 0);

const ICONES = {
  aguardando: 'i-lucide-clock',
  enviado: 'i-lucide-send',
  sem_ninguem: 'i-lucide-users',
  cancelado: 'i-lucide-ban',
  falhou: 'i-lucide-triangle-alert',
};

const campanha = computed(() => props.segunda.campanha);
const falhou = computed(() => props.segunda.status === 'falhou');
const icone = computed(() => ICONES[props.segunda.status] || 'i-lucide-send');

const quem = computed(() =>
  t(
    `REENVIO_HORARIO.REENVIO.QUEM_RESUMO.${String(props.segunda.quem || 'nao_respondeu').toUpperCase()}`
  )
);

const aguardando = () => {
  const { previsto_em: previsto, dias } = props.segunda;
  if (previsto) {
    const quando = quandoFalado(previsto, {
      fuso: fuso.value,
      locale: locale.value,
      t,
    });
    return t(`${NS}.AGUARDANDO_DATA`, { quando, quem: quem.value });
  }
  return t(`${NS}.AGUARDANDO_SEM_DATA`, { dias, quem: quem.value }, dias);
};

const enviada = () => {
  if (!campanha.value) return t(`${NS}.APAGADA`);
  const { receberam, responderam } = campanha.value;
  return t(`${NS}.ENVIADA`, {
    receberam: t(`${NS}.RECEBERAM`, { n: inteiro(receberam) }, receberam),
    responderam: t(
      `${NS}.RESPONDERAM`,
      { n: inteiro(responderam) },
      responderam
    ),
  });
};

const frase = computed(() => {
  switch (props.segunda.status) {
    case 'aguardando':
      return aguardando();
    case 'enviado':
      return enviada();
    case 'sem_ninguem':
      return t(`${NS}.SEM_NINGUEM`);
    case 'cancelado':
      return t(`${NS}.CANCELADO`);
    default:
      return t(`${NS}.FALHOU`);
  }
});

const rota = computed(() =>
  campanha.value
    ? {
        name: 'campaigns_journey_result',
        params: {
          channel: campanha.value.channel,
          campaignId: String(campanha.value.id),
        },
      }
    : null
);
</script>

<template>
  <section
    class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 border rounded-2xl border-n-weak bg-n-solid-1"
    :data-segunda-mensagem="segunda.status"
  >
    <div class="flex items-start min-w-0 gap-3">
      <span
        class="mt-0.5 size-5 shrink-0"
        :class="[icone, falhou ? 'text-n-ruby-11' : 'text-n-slate-11']"
        aria-hidden="true"
      />
      <div class="flex flex-col min-w-0 gap-1">
        <h2 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${NS}.TITULO`) }}
        </h2>
        <p
          class="m-0 text-base break-words"
          :class="[
            falhou ? 'text-n-ruby-11' : 'text-n-slate-12',
            { 'tabular-nums': segunda.status === 'enviado' },
          ]"
          data-frase
        >
          {{ frase }}
        </p>
        <p
          v-if="campanha?.processing"
          class="m-0 text-sm text-n-slate-11"
          data-saindo
        >
          {{ t(`${NS}.SAINDO`) }}
        </p>
      </div>
    </div>
    <router-link
      v-if="rota"
      :to="rota"
      class="flex items-center justify-between max-w-full gap-2 px-3 text-sm text-left font-medium border min-h-11 rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      data-ver-segunda
    >
      <span class="min-w-0 py-2 break-words">{{ campanha.name }}</span>
      <span class="i-lucide-arrow-right size-4 shrink-0" aria-hidden="true" />
    </router-link>
  </section>
</template>
