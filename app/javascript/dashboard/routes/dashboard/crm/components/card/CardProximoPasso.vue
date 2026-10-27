<script setup>
import { computed } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';
import { textoDoFechamento } from './sugestaoDeFechar';

// #1423 — o "Próximo passo": uma coisa só, com o único botão azul da tela, e
// até duas "Depois disso". A ordem vem de proximoPasso.js. Sem botão cinza ao
// lado: abrir a conversa, ver a agenda e o histórico já têm o seu lugar nos
// cartões. A única exceção é "Deixar como está" da sugestão, que não existe
// em outro lugar.
const props = defineProps({
  passos: { type: Object, required: true },
  nome: { type: String, required: true },
  formato: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
  podeIa: { type: Boolean, default: false },
  temConversa: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  status: { type: String, default: '' },
  // #1498 — funil de Atender: "Este atendimento terminou".
  venda: { type: Boolean, default: true },
  // #2195 — "Chamar no WhatsApp" de quem chegou pelo formulário abre a Nova
  // conversa com este contato (a primeira mensagem sai de Modelos).
  contatoId: { type: String, default: null },
});

const emit = defineEmits([
  'responder',
  'feito',
  'retorno',
  'abrir',
  'aceitar',
  'dispensar',
  'reabrir',
]);

const { t } = useI18n();
const P = 'CRM_CARD.PASSO';
const podeComecar = usePodeComecarConversa();

const VISUAL = {
  reuniao_hoje: { icone: 'i-lucide-calendar-clock', tom: 'teal' },
  retorno_atrasado: { icone: 'i-lucide-alarm-clock', tom: 'ruby' },
  espera: { icone: 'i-lucide-message-circle-reply', tom: 'blue' },
  formulario: { icone: 'i-lucide-clipboard-check', tom: 'blue' },
  sugestao: { icone: 'i-lucide-sparkles', tom: 'iris' },
  retorno_hoje: { icone: 'i-lucide-bell-ring', tom: 'amber' },
  em_dia: { icone: 'i-lucide-circle-check', tom: 'teal' },
  fechado: { icone: 'i-lucide-flag', tom: 'blue' },
  reuniao_futura: { icone: 'i-lucide-calendar', tom: 'teal' },
  retorno_futuro: { icone: 'i-lucide-bell', tom: 'amber' },
};
const TONS = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
};
const BORDAS = {
  ruby: 'border-n-ruby-7',
  teal: 'border-n-teal-7',
  blue: 'border-n-blue-7',
  iris: 'border-n-iris-7',
  amber: 'border-n-amber-7',
};
// Em "Depois disso" o atrasado continua vermelho: a ordem põe a reunião de
// hoje antes (tem hora marcada), mas o atraso não perde o alerta.
const LINHA = {
  retorno_atrasado: 'text-n-ruby-11 font-medium',
};
const ICONE_LINHA = {
  retorno_atrasado: 'text-n-ruby-11',
};
const DESTINO = {
  reuniao_hoje: 'agenda',
  reuniao_futura: 'agenda',
  retorno_atrasado: 'agenda',
  retorno_hoje: 'agenda',
  retorno_futuro: 'agenda',
  espera: 'conversas',
  sugestao: 'etapa',
  formulario: 'origem',
};

const principal = computed(() => props.passos.principal);
const visual = computed(() => VISUAL[principal.value.tipo]);

// O botão azul do passo e, só na sugestão, "Deixar como está".
const acoes = computed(() => {
  const passo = principal.value;
  const gerencia = props.podeGerenciar;
  const feito = gerencia
    ? {
        rotulo: t(`${P}.FEITO`),
        icone: 'i-lucide-check',
        evento: 'feito',
        dado: passo.retorno,
      }
    : null;
  const lista = {
    reuniao_hoje: [
      {
        rotulo: t(`${P}.VER_REUNIAO`),
        icone: 'i-lucide-calendar-clock',
        evento: 'abrir',
        dado: 'agenda',
      },
    ],
    retorno_atrasado: [feito],
    espera: [
      props.temConversa
        ? {
            rotulo: t(`${P}.RESPONDER`),
            icone: 'i-lucide-send',
            evento: 'responder',
          }
        : null,
    ],
    formulario: [
      props.contatoId && podeComecar.value
        ? {
            rotulo: t(`${P}.CHAMAR_WHATSAPP`),
            icone: 'i-lucide-message-circle',
            evento: 'chamar',
          }
        : null,
    ],
    sugestao: props.podeIa
      ? [
          {
            rotulo: textoDoFechamento(passo.sugestao)
              ? t(textoDoFechamento(passo.sugestao).botao)
              : t(`${P}.MOVER`, { etapa: passo.sugestao?.to_stage_name }),
            icone: 'i-lucide-arrow-right',
            evento: 'aceitar',
          },
          { rotulo: t(`${P}.DEIXAR`), evento: 'dispensar' },
        ]
      : [{ rotulo: t(`${P}.VER_ETAPA`), evento: 'abrir', dado: 'etapa' }],
    retorno_hoje: [feito],
    fechado: [
      gerencia
        ? {
            rotulo: t('CRM_CARD.DESFECHO.REABRIR'),
            icone: 'i-lucide-rotate-ccw',
            evento: 'reabrir',
          }
        : null,
    ],
    em_dia: [
      gerencia
        ? {
            rotulo: t(`${P}.MARCAR_RETORNO`),
            icone: 'i-lucide-bell-plus',
            evento: 'retorno',
          }
        : null,
    ],
  }[passo.tipo];
  const [azul, cinza] = lista || [];
  return { azul: azul || null, cinza: cinza || null };
});

// Cada ação diz qual evento solta; a lista explícita deixa claro quem ouve.
const EVENTOS = {
  responder: () => emit('responder'),
  feito: dado => emit('feito', dado),
  retorno: () => emit('retorno'),
  abrir: dado => emit('abrir', dado),
  aceitar: () => emit('aceitar'),
  dispensar: () => emit('dispensar'),
  reabrir: () => emit('reabrir'),
};
const disparar = acao => EVENTOS[acao.evento](acao.dado);

const chaveDe = passo => {
  if (passo.tipo === 'fechado' && !props.venda) return `${P}.FECHADO_ATENDER`;
  // #2195 — quem só lê conversas não chama: a frase não manda chamar.
  if (passo.tipo === 'formulario' && !podeComecar.value)
    return `${P}.FORMULARIO_LEITURA`;
  return `${P}.${passo.tipo.toUpperCase()}`;
};

const fraseDe = passo => {
  const quando = passo.quando ? props.formato.quando(passo.quando) : '';
  // A sugestão de fechar o card (F3) diz o que acabou, e não a etapa.
  const fechar = passo.tipo === 'sugestao' && textoDoFechamento(passo.sugestao);
  return {
    chave: fechar ? fechar.frase : chaveDe(passo),
    curta: fechar ? fechar.curta : `${P}.CURTO.${passo.tipo.toUpperCase()}`,
    motivo: fechar && fechar.motivo ? t(fechar.motivo) : '',
    retorno: fechar && fechar.retorno ? t(fechar.retorno) : '',
    quando,
    ha: passo.quando ? props.formato.ha(passo.quando) : '',
    titulo: passo.retorno?.title || '',
    etapa: passo.sugestao?.to_stage_name || '',
  };
};
const frase = computed(() => fraseDe(principal.value));
const depois = computed(() =>
  props.passos.depois.map(passo => ({
    ...fraseDe(passo),
    tipo: passo.tipo,
    ...VISUAL[passo.tipo],
  }))
);
</script>

<template>
  <section
    data-card-proximo
    :data-passo="principal.tipo"
    class="flex flex-col gap-3 rounded-2xl border-2 bg-n-solid-1 px-4 py-3 shadow-sm sm:px-5"
    :class="BORDAS[visual.tom]"
    :aria-labelledby="`${principal.tipo}-proximo`"
  >
    <div class="flex flex-wrap items-start gap-3 sm:flex-nowrap sm:gap-4">
      <span
        class="grid size-10 shrink-0 place-items-center rounded-2xl sm:size-12"
        :class="TONS[visual.tom]"
        aria-hidden="true"
      >
        <span class="size-5 sm:size-6" :class="visual.icone" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <h3
          :id="`${principal.tipo}-proximo`"
          class="mb-0 flex min-h-6 items-center text-sm font-medium text-n-slate-11"
        >
          {{ t(`${P}.ROTULO`) }}
        </h3>
        <span
          v-if="principal.tipo === 'retorno_atrasado'"
          class="inline-flex w-fit items-center gap-1.5 rounded-lg bg-n-ruby-3 px-2 py-0.5 text-sm font-medium text-n-ruby-11"
        >
          <span class="i-lucide-clock size-3.5" aria-hidden="true" />
          {{ t(`${P}.ATRASADO_DESDE`, { quando: frase.quando }) }}
        </span>
        <I18nT
          :keypath="frase.chave"
          tag="p"
          scope="global"
          class="mb-0 text-lg font-semibold leading-snug text-n-slate-12"
        >
          <template #nome>{{ nome }}</template>
          <template #quando>{{ frase.quando }}</template>
          <template #ha>{{ frase.ha }}</template>
          <template #titulo>{{ frase.titulo }}</template>
          <template #etapa>{{ frase.etapa }}</template>
          <template #motivo>{{ frase.motivo }}</template>
          <template #status>{{ status }}</template>
        </I18nT>
        <p
          v-if="principal.retorno?.description"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t(`${P}.VOCE_ANOTOU`, { texto: principal.retorno.description }) }}
        </p>
        <p
          v-if="principal.tipo === 'sugestao' && principal.sugestao.reasoning"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ principal.sugestao.reasoning }}
        </p>
        <p
          v-if="principal.tipo === 'formulario' && !podeComecar"
          data-passo-sem-conversa
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t(`${P}.FORMULARIO_SEM_CONVERSA`) }}
        </p>
        <p v-if="frase.retorno" class="mb-0 text-sm text-n-slate-11">
          {{ frase.retorno }}
        </p>
      </div>
      <div
        v-if="acoes.azul || acoes.cinza"
        class="flex w-full flex-wrap gap-2 sm:w-auto sm:shrink-0 sm:flex-col sm:items-stretch sm:self-center"
      >
        <NovaConversaEntrada
          v-if="acoes.azul?.evento === 'chamar'"
          :contact-id="contatoId"
        >
          <template #trigger>
            <Button
              data-passo-principal
              :label="acoes.azul.rotulo"
              :icon="acoes.azul.icone"
              class="!min-h-11 w-full justify-center"
            />
          </template>
        </NovaConversaEntrada>
        <Button
          v-else-if="acoes.azul"
          data-passo-principal
          :label="acoes.azul.rotulo"
          :icon="acoes.azul.icone"
          class="!min-h-11 justify-center"
          :is-loading="ocupado"
          @click="disparar(acoes.azul)"
        />
        <Button
          v-if="acoes.cinza"
          data-passo-outro
          :label="acoes.cinza.rotulo"
          :icon="acoes.cinza.icone"
          slate
          ghost
          class="!min-h-11 justify-center"
          @click="disparar(acoes.cinza)"
        />
      </div>
    </div>
    <div v-if="depois.length" class="border-t border-n-weak pt-2 sm:ms-16">
      <h4 class="mb-0 text-xs font-medium text-n-slate-11">
        {{ t(`${P}.DEPOIS`) }}
      </h4>
      <ul class="m-0 flex list-none flex-col p-0">
        <li v-for="item in depois" :key="item.tipo">
          <button
            type="button"
            :data-depois="item.tipo"
            class="flex min-h-11 w-full items-center gap-3 rounded-xl px-2 text-start text-[0.9375rem] transition hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :class="LINHA[item.tipo] || 'text-n-slate-12'"
            @click="emit('abrir', DESTINO[item.tipo])"
          >
            <span
              class="size-4 shrink-0"
              :class="[item.icone, ICONE_LINHA[item.tipo] || 'text-n-slate-11']"
              aria-hidden="true"
            />
            <I18nT
              :keypath="item.curta"
              tag="span"
              scope="global"
              class="min-w-0 flex-1"
            >
              <template #nome>{{ nome }}</template>
              <template #quando>{{ item.quando }}</template>
              <template #ha>{{ item.ha }}</template>
              <template #titulo>{{ item.titulo }}</template>
              <template #etapa>{{ item.etapa }}</template>
            </I18nT>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
    </div>
  </section>
</template>
