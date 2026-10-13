<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CENARIO_FORA, cenaDaPrevia } from '../passagem';

// #1385 — a conversa da cliente de exemplo no dia escolhido (sábado com a equipe fora, ou terça com a equipe online).
// Mostra quem recebe, se a assistente continua respondendo e quando a pessoa assume. Tudo sai da regra que está na tela
// e do que o back-end faz de verdade (HandoffExecutor, HandoffDrainJob, HandoffEscalationJob, HandoffExpiryJob).
const props = defineProps({
  regra: { type: Object, required: true },
  recebe: { type: String, default: '' },
  outra: { type: String, default: '' },
  iaLigada: { type: Boolean, default: true },
  semCaixa: { type: Boolean, default: false },
  cenario: { type: String, default: CENARIO_FORA },
});

const { t } = useI18n();
const C = 'CRM_KANBAN.PASSAGEM.CENA';
const cliente = computed(() => t('CRM_KANBAN.PASSAGEM.PREVIA.CLIENTE'));
// Sem nome na regra: "alguém da equipe" no rodízio, "a pessoa escolhida" quando é sempre a mesma pessoa.
const alguem = computed(() =>
  t(
    props.regra.pool_type === 'user'
      ? 'CRM_KANBAN.PASSAGEM.PREVIA.PESSOA_ESCOLHIDA'
      : 'CRM_KANBAN.PASSAGEM.PREVIA.ALGUEM'
  )
);

// O texto pode começar pelo "alguém da equipe" de quando falta o nome: a primeira letra sobe.
const comMaiuscula = texto => texto.charAt(0).toUpperCase() + texto.slice(1);

const passos = computed(() =>
  cenaDaPrevia({
    regra: props.regra,
    recebe: props.recebe,
    outra: props.outra,
    iaLigada: props.iaLigada,
    semCaixa: props.semCaixa,
    cenario: props.cenario,
  }).map((passo, indice) => ({
    ...passo,
    id: indice,
    texto: comMaiuscula(
      t(`${C}.${passo.chave}`, {
        nome: passo.nome || alguem.value,
        convidada: passo.convidada || alguem.value,
        minutos: passo.minutos,
        cliente: cliente.value,
      })
    ),
  }))
);

const TOM = {
  verde: {
    caixa: 'bg-n-teal-2 text-n-slate-12',
    icone: 'i-lucide-message-circle-heart text-n-teal-11',
  },
  azul: {
    caixa: 'bg-n-blue-2 text-n-slate-12',
    icone: 'i-lucide-user-round-check text-n-blue-11',
  },
  ambar: {
    caixa: 'bg-n-amber-2 text-n-amber-12',
    icone: 'i-lucide-triangle-alert text-n-amber-11',
  },
  prazo: {
    caixa: 'bg-n-alpha-2 text-n-slate-12',
    icone: 'i-lucide-clock text-n-slate-11',
  },
  cinza: {
    caixa: 'bg-n-alpha-2 text-n-slate-12',
    icone: 'i-lucide-bot text-n-slate-11',
  },
};
</script>

<template>
  <section
    data-previa-conversa
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <ol class="m-0 flex list-none flex-col gap-2 rounded-xl bg-n-alpha-1 p-3">
      <li
        v-for="passo in passos"
        :key="passo.id"
        :data-passo-cena="passo.chave"
        class="flex"
        :class="{
          'justify-center': passo.tipo === 'dia',
          'justify-start': passo.tipo === 'cliente',
          'justify-end': passo.tipo === 'robo',
        }"
      >
        <span
          v-if="passo.tipo === 'dia'"
          class="rounded-lg bg-n-solid-1 px-2 py-0.5 text-sm text-n-slate-11"
        >
          {{ passo.texto }}
        </span>
        <span
          v-else-if="passo.tipo === 'cliente'"
          class="max-w-[85%] rounded-xl rounded-es-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
        >
          {{ passo.texto }}
        </span>
        <span
          v-else-if="passo.tipo === 'robo'"
          class="flex max-w-[85%] flex-col items-end gap-0.5"
        >
          <span class="text-xs text-n-slate-11">{{
            t('CRM_KANBAN.PASSAGEM.PREVIA.ROBO')
          }}</span>
          <span
            class="rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
          >
            {{ passo.texto }}
          </span>
        </span>
        <span
          v-else
          class="flex w-full items-start gap-2 rounded-xl px-3 py-2 text-sm"
          :class="TOM[passo.tom].caixa"
        >
          <span
            class="mt-0.5 size-4 shrink-0"
            :class="TOM[passo.tom].icone"
            aria-hidden="true"
          />
          {{ passo.texto }}
        </span>
      </li>
    </ol>
  </section>
</template>
