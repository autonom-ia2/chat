<script setup>
// Convite de reunião no e-mail (#1984): bloco de data como na folhinha, horário e duração,
// botão de entrar na chamada, quem vai (avatares) e a resposta da própria caixa num
// controle segmentado (Sim / Talvez / Não). Só responde quem foi convidado: convite
// recebido em cópia mostra as informações e diz por que não dá para responder daqui.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Spinner from 'next/spinner/Spinner.vue';
import ConviteAPI from 'dashboard/api/conviteDaReuniao';
import { useAgora } from '../useAgora';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  RESPOSTAS,
  aplicativoDaChamada,
  blocoDaData,
  diaDoConvite,
  horarioDoConvite,
  minutosDoConvite,
  nomeDaPessoa,
} from './conviteDaReuniao';

const props = defineProps({
  convite: { type: Object, required: true },
  mensagemId: { type: Number, required: true },
  fuso: { type: String, default: undefined },
});

const AVATARES_VISIVEIS = 4;
const ROTULO = {
  aceito: 'CONVERSA_CANAL.EMAIL.CONVITE.SIM',
  talvez: 'CONVERSA_CANAL.EMAIL.CONVITE.TALVEZ',
  recusado: 'CONVERSA_CANAL.EMAIL.CONVITE.NAO',
};
const CONFIRMACAO = {
  aceito: 'CONVERSA_CANAL.EMAIL.CONVITE.CONFIRMOU_SIM',
  talvez: 'CONVERSA_CANAL.EMAIL.CONVITE.CONFIRMOU_TALVEZ',
  recusado: 'CONVERSA_CANAL.EMAIL.CONVITE.CONFIRMOU_NAO',
};
const ICONE = {
  aceito: 'i-lucide-circle-check',
  talvez: 'i-lucide-circle-help',
  recusado: 'i-lucide-circle-x',
};
// Cor da escolha: no segmento marcado e na faixa da resposta.
const COR = {
  aceito: {
    segmento: 'bg-n-teal-9 text-white shadow-sm',
    faixa: 'bg-n-teal-3 text-n-teal-11 border-n-teal-6',
  },
  talvez: {
    segmento: 'bg-n-amber-9 text-n-amber-12 shadow-sm',
    faixa: 'bg-n-amber-3 text-n-amber-11 border-n-amber-6',
  },
  recusado: {
    segmento: 'bg-n-ruby-9 text-white shadow-sm',
    faixa: 'bg-n-ruby-3 text-n-ruby-11 border-n-ruby-6',
  },
};

const { t, locale } = useI18n();
const agora = useAgora();

const resposta = ref(props.convite.minhaResposta || null);
const mudando = ref(false);
const enviando = ref(null);
const erro = ref(false);

const cancelado = computed(() => props.convite.metodo === 'CANCEL');
const idioma = computed(() => idiomaDoPainel(locale.value));
const bloco = computed(() =>
  blocoDaData({
    inicio: props.convite.inicio,
    fuso: props.fuso,
    idioma: idioma.value,
  })
);
const dia = computed(() =>
  diaDoConvite({
    inicio: props.convite.inicio,
    agora: agora.value,
    fuso: props.fuso,
    t,
    idioma: idioma.value,
  })
);
const horario = computed(() =>
  horarioDoConvite({
    inicio: props.convite.inicio,
    fim: props.convite.fim,
    fuso: props.fuso,
    idioma: idioma.value,
  })
);
const duracao = computed(() => {
  const minutos = minutosDoConvite(props.convite);
  if (!minutos) return '';
  if (minutos < 60)
    return t('CONVERSA_CANAL.EMAIL.CONVITE.MINUTOS', { n: minutos });
  const horas = Math.floor(minutos / 60);
  const resto = minutos % 60;
  return resto
    ? t('CONVERSA_CANAL.EMAIL.CONVITE.HORAS_E_MINUTOS', { h: horas, m: resto })
    : t('CONVERSA_CANAL.EMAIL.CONVITE.HORAS', { n: horas });
});
const aplicativo = computed(() => aplicativoDaChamada(props.convite.link));
const rotuloDeEntrar = computed(() =>
  aplicativo.value
    ? t('CONVERSA_CANAL.EMAIL.CONVITE.ENTRAR_NO', { app: aplicativo.value })
    : t('CONVERSA_CANAL.EMAIL.CONVITE.ENTRAR')
);
const pessoas = computed(() => [
  props.convite.organizador,
  ...(props.convite.convidados || []),
]);
const avatares = computed(() => pessoas.value.slice(0, AVATARES_VISIVEIS));
const aMais = computed(() => pessoas.value.length - avatares.value.length);
const convidados = computed(() =>
  (props.convite.convidados || []).map(nomeDaPessoa).join(', ')
);
const perguntando = computed(
  () =>
    !cancelado.value &&
    props.convite.podeResponder &&
    (!resposta.value || mudando.value)
);

const responder = async escolha => {
  if (enviando.value) return;
  enviando.value = escolha;
  erro.value = false;
  try {
    const { data } = await ConviteAPI.responder(props.mensagemId, escolha);
    resposta.value = data.resposta;
    mudando.value = false;
  } catch {
    erro.value = true;
  } finally {
    enviando.value = null;
  }
};
</script>

<template>
  <section
    class="relative mb-5 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    data-convite-da-reuniao
  >
    <div
      class="absolute inset-y-0 start-0 w-1"
      :class="cancelado ? 'bg-n-ruby-9' : 'bg-n-brand'"
    />

    <div class="flex gap-4 p-4 sm:p-5">
      <div
        class="flex w-16 flex-shrink-0 flex-col self-start overflow-hidden rounded-xl border text-center sm:w-[4.5rem]"
        :class="
          cancelado ? 'border-n-weak opacity-60' : 'border-n-blue-6 shadow-sm'
        "
        aria-hidden="true"
      >
        <span
          class="py-1 text-[0.6875rem] font-semibold uppercase tracking-wider text-white"
          :class="cancelado ? 'bg-n-slate-9' : 'bg-n-brand'"
        >
          {{ bloco.mes }}
        </span>
        <span
          class="bg-n-solid-2 pt-1.5 text-2xl font-bold leading-none text-n-slate-12 tabular-nums"
        >
          {{ bloco.dia }}
        </span>
        <span
          class="bg-n-solid-2 pb-1.5 pt-1 text-[0.6875rem] text-n-slate-11"
        >
          {{ bloco.semana }}
        </span>
      </div>

      <div class="min-w-0 flex-1">
        <div
          class="flex flex-wrap items-center gap-2 text-xs font-medium text-n-slate-11"
        >
          <span>{{ t('CONVERSA_CANAL.EMAIL.CONVITE.ROTULO') }}</span>
          <span
            v-if="cancelado"
            class="inline-flex items-center gap-1 rounded-full bg-n-ruby-3 px-2 py-0.5 text-n-ruby-11"
          >
            <Icon icon="i-lucide-calendar-x" class="size-3" />
            {{ t('CONVERSA_CANAL.EMAIL.CONVITE.CANCELADA') }}
          </span>
        </div>
        <h3
          class="mt-1 text-lg font-semibold leading-snug text-n-slate-12 break-words [text-wrap:balance]"
          :class="{ 'line-through decoration-n-slate-9': cancelado }"
        >
          {{ convite.titulo }}
        </h3>
        <p
          class="mt-1 flex flex-wrap items-center gap-x-2 text-sm text-n-slate-12 tabular-nums"
        >
          <Icon icon="i-lucide-clock-3" class="size-4 text-n-slate-11" />
          <span class="font-medium">{{ dia }}</span>
          <span class="whitespace-nowrap">
            <span class="text-n-slate-9">·</span>
            {{ horario }}
          </span>
          <span v-if="duracao" class="whitespace-nowrap text-n-slate-11">
            ({{ duracao }})
          </span>
        </p>

        <div
          v-if="convite.link && !cancelado"
          class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-2"
        >
          <a
            :href="convite.link"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex min-h-10 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white shadow-sm transition-colors hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            data-entrar-na-reuniao
          >
            <Icon icon="i-lucide-video" class="size-4" />
            {{ rotuloDeEntrar }}
          </a>
          <span v-if="convite.local" class="text-xs text-n-slate-11">
            {{ convite.local }}
          </span>
        </div>
        <p
          v-else-if="convite.local"
          class="mt-2 flex items-center gap-2 text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-map-pin" class="size-4" />
          {{ convite.local }}
        </p>
      </div>
    </div>

    <div
      class="flex items-center gap-3 px-4 pb-4 sm:px-5 sm:ps-[6.75rem]"
      data-convidados-do-convite
    >
      <div class="flex flex-shrink-0 -space-x-1" aria-hidden="true">
        <div
          v-for="pessoa in avatares"
          :key="pessoa.email"
          class="rounded-full ring-2 ring-n-solid-1"
        >
          <Avatar :name="nomeDaPessoa(pessoa)" :size="28" rounded-full />
        </div>
        <span
          v-if="aMais > 0"
          class="flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-[0.6875rem] font-medium text-n-slate-11 ring-2 ring-n-solid-1"
        >
          +{{ aMais }}
        </span>
      </div>
      <p class="min-w-0 text-xs leading-snug text-n-slate-11">
        <span class="font-medium text-n-slate-12">
          {{ nomeDaPessoa(convite.organizador) }}
        </span>
        {{ t('CONVERSA_CANAL.EMAIL.CONVITE.CONVIDOU') }}
        <span v-if="convidados" class="break-words">{{ convidados }}</span>
      </p>
    </div>

    <footer class="border-t border-n-weak bg-n-alpha-1 px-4 py-3 sm:px-5">
      <p
        v-if="cancelado"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <Icon icon="i-lucide-calendar-x" class="size-4 text-n-ruby-11" />
        {{ t('CONVERSA_CANAL.EMAIL.CONVITE.CANCELADA_TEXTO') }}
      </p>

      <p
        v-else-if="!convite.podeResponder"
        class="flex items-start gap-2 text-sm text-n-slate-11"
        data-convite-so-informativo
      >
        <Icon icon="i-lucide-info" class="mt-0.5 size-4 flex-shrink-0" />
        <span>
          {{
            t('CONVERSA_CANAL.EMAIL.CONVITE.NAO_CONVIDADA', {
              caixa: convite.caixa,
            })
          }}
        </span>
      </p>

      <div
        v-else-if="perguntando"
        class="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSA_CANAL.EMAIL.CONVITE.PERGUNTA') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              t('CONVERSA_CANAL.EMAIL.CONVITE.RESPONDE_COMO', {
                caixa: convite.caixa,
              })
            }}
          </p>
        </div>
        <div
          class="grid flex-shrink-0 grid-cols-3 gap-1 rounded-xl bg-n-alpha-2 p-1 sm:w-72"
          role="group"
          :aria-label="t('CONVERSA_CANAL.EMAIL.CONVITE.PERGUNTA')"
        >
          <button
            v-for="opcao in RESPOSTAS"
            :key="opcao"
            type="button"
            class="inline-flex min-h-10 items-center justify-center gap-1.5 rounded-lg px-2 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-wait"
            :class="
              resposta === opcao
                ? COR[opcao].segmento
                : 'text-n-slate-12 hover:bg-n-solid-1'
            "
            :aria-pressed="resposta === opcao"
            :disabled="Boolean(enviando)"
            :data-responder="opcao"
            @click="responder(opcao)"
          >
            <Spinner v-if="enviando === opcao" :size="14" />
            {{ t(ROTULO[opcao]) }}
          </button>
        </div>
        <p v-if="erro" class="text-sm text-n-ruby-11 sm:basis-full" role="alert">
          {{ t('CONVERSA_CANAL.EMAIL.CONVITE.ERRO') }}
        </p>
      </div>

      <div
        v-else
        class="flex flex-wrap items-center justify-between gap-2"
        data-convite-respondido
      >
        <span
          class="inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium"
          :class="COR[resposta].faixa"
          role="status"
        >
          <Icon :icon="ICONE[resposta]" class="size-4" />
          {{ t(CONFIRMACAO[resposta]) }}
        </span>
        <button
          type="button"
          class="relative text-sm font-medium text-n-blue-11 after:absolute after:-inset-3 after:content-[''] hover:underline"
          @click="mudando = true"
        >
          {{ t('CONVERSA_CANAL.EMAIL.CONVITE.MUDAR') }}
        </button>
      </div>
    </footer>
  </section>
</template>
