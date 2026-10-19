<script setup>
// Calendário Ouro — "Meu dia": o que ficou para trás, o que é hoje (o dia
// todo primeiro, depois por hora, com a linha do "agora") e os próximos dias.
// Num outro dia escolhido, só aquele dia.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarioItem from './CalendarioItem.vue';
import { porHorario, semRepeticoes } from './itensDoCalendario';
import { formatarDia, formatarHora, somarDias } from './tempoNaConta';

const props = defineProps({
  itens: { type: Array, default: () => [] },
  hoje: { type: String, required: true },
  dia: { type: String, required: true },
  agoraMinutos: { type: Number, required: true },
  agora: { type: Date, required: true },
  fuso: { type: String, required: true },
  idioma: { type: String, required: true },
  nomeDe: { type: Function, required: true },
  concluindo: { type: Array, default: () => [] },
  recemFeitos: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'concluir',
  'abrir',
  'acao',
  'proximoPasso',
  'esquecerFeito',
  'adiarAtrasados',
  'novo',
]);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.DIA';
const DIAS_A_FRENTE = 7;

const ehHoje = computed(() => props.dia === props.hoje);
const pendentes = computed(() =>
  props.itens.filter(item => !item.feito).sort(porHorario)
);
const atrasados = computed(() =>
  ehHoje.value
    ? pendentes.value.filter(i => i.atrasado && i.chave < props.hoje)
    : []
);
const doDia = computed(() =>
  props.itens.filter(i => i.chave === props.dia).sort(porHorario)
);

// Índice do primeiro item depois de agora: a linha do "agora" entra antes dele.
const linhaDoAgora = computed(() => {
  if (!ehHoje.value || !doDia.value.length) return -1;
  const indice = doDia.value.findIndex(
    i => !i.diaTodo && i.minutos > props.agoraMinutos
  );
  return indice === -1 ? doDia.value.length : indice;
});
const horaDeAgora = computed(() =>
  formatarHora(props.agora, props.fuso, props.idioma)
);

// Atrasado há mais de 30 dias não some calado: fica recolhido no fim do
// "Ficou para trás" ("E mais N antigos · Ver").
const DIAS_RECENTES = 30;
const verAntigos = ref(false);
const limiteRecente = computed(() => somarDias(props.hoje, -DIAS_RECENTES));
const atrasadosRecentes = computed(() =>
  atrasados.value.filter(i => i.chave >= limiteRecente.value)
);
const atrasadosAntigos = computed(() =>
  atrasados.value.filter(i => i.chave < limiteRecente.value)
);
const atrasadosVisiveis = computed(() =>
  verAntigos.value
    ? [...atrasadosAntigos.value, ...atrasadosRecentes.value]
    : atrasadosRecentes.value
);
// "Passar tudo" só leva lembrete de uma pessoa (#1855); o aviso de um envio ao
// cliente que falhou fica, para ser reagendado um a um.
const adiaveis = computed(() => atrasadosVisiveis.value.filter(i => !i.envio));

const proximosDias = computed(() => {
  if (!ehHoje.value) return [];
  const ate = somarDias(props.hoje, DIAS_A_FRENTE);
  const itens = semRepeticoes(
    pendentes.value.filter(i => i.chave > props.hoje && i.chave <= ate)
  );
  const grupos = new Map();
  itens.forEach(item => {
    if (!grupos.has(item.chave)) grupos.set(item.chave, []);
    grupos.get(item.chave).push(item);
  });
  return [...grupos.entries()].map(([chave, lista]) => ({ chave, lista }));
});

const proximo = computed(() => proximosDias.value[0]?.lista[0] || null);

const nomeDoDia = chave => {
  if (chave === props.hoje) return t(`${N}.HOJE`);
  if (chave === somarDias(props.hoje, 1)) return t(`${N}.AMANHA`);
  const texto = formatarDia(chave, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  return texto.charAt(0).toUpperCase() + texto.slice(1);
};
// No meio da frase, o dia vai em minúscula ("para sábado, 17 de outubro").
const diaNaFrase = chave =>
  formatarDia(chave, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
const linhaDoProximo = computed(() =>
  proximo.value
    ? t(`${N}.PROXIMO`, {
        dia: nomeDoDia(proximo.value.chave),
        titulo: proximo.value.titulo,
      })
    : t(`${N}.NADA_A_FRENTE`)
);

const ligar = item => ({
  item,
  hoje: props.hoje,
  fuso: props.fuso,
  idioma: props.idioma,
  para: props.nomeDe(item.evento.assignee_id),
  concluindo: props.concluindo.includes(item.id),
});
const repassar = {
  concluir: item => emit('concluir', item),
  abrir: item => emit('abrir', item),
  acao: carga => emit('acao', carga),
};
const ATALHOS = ['AMANHA', 'TRES_DIAS', 'SEMANA'];
</script>

<template>
  <div class="flex min-w-0 flex-col gap-8">
    <!-- Acabou de fazer: oferece o próximo passo -->
    <div
      v-for="feito in recemFeitos"
      :key="feito.id"
      data-recem-feito
      class="flex flex-col gap-3 rounded-2xl border border-n-teal-7 bg-n-teal-2 p-4 sm:flex-row sm:items-center"
    >
      <span
        class="grid size-10 shrink-0 place-items-center rounded-full bg-n-teal-9 text-white"
        aria-hidden="true"
      >
        <span class="i-lucide-check size-5" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="mb-0 line-clamp-2 text-base font-semibold text-n-slate-12">
          {{ t(`${N}.FEITO_TITULO`, { titulo: feito.titulo }) }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t(`${N}.FEITO_PERGUNTA`) }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-for="atalho in ATALHOS"
          :key="atalho"
          :data-proximo="atalho"
          :label="t(`${N}.ATALHO.${atalho}`)"
          teal
          faded
          class="!min-h-11"
          @click="emit('proximoPasso', { item: feito, atalho })"
        />
        <Button
          :label="t(`${N}.NAO_PRECISA`)"
          slate
          ghost
          class="!min-h-11"
          @click="emit('esquecerFeito', feito)"
        />
      </div>
    </div>

    <!-- Ficou para trás -->
    <section
      v-if="atrasados.length"
      data-secao="atrasados"
      class="flex flex-col gap-3"
    >
      <header class="flex flex-wrap items-center justify-between gap-2">
        <h3
          class="mb-0 flex items-center gap-2 text-lg font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-alarm-clock size-5 text-n-ruby-10"
            aria-hidden="true"
          />
          {{ t(`${N}.ATRASADOS`) }}
          <span
            class="rounded-full bg-n-ruby-3 px-2 text-sm font-semibold text-n-ruby-11"
          >
            {{ atrasados.length }}
          </span>
        </h3>
        <Button
          v-if="adiaveis.length"
          data-adiar-todos
          :label="t(`${N}.ADIAR_TODOS`)"
          icon="i-lucide-calendar-arrow-up"
          slate
          ghost
          class="!min-h-11"
          @click="emit('adiarAtrasados', adiaveis)"
        />
      </header>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <CalendarioItem
          v-for="item in atrasadosVisiveis"
          :key="item.id"
          v-bind="ligar(item)"
          v-on="repassar"
        />
      </ul>
      <button
        v-if="atrasadosAntigos.length"
        type="button"
        data-antigos
        :aria-expanded="verAntigos"
        class="flex min-h-11 items-center gap-2 self-start rounded-xl px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2"
        @click="verAntigos = !verAntigos"
      >
        <span>{{
          t(
            `${N}.ANTIGOS`,
            { n: atrasadosAntigos.length },
            atrasadosAntigos.length
          )
        }}</span>
        <span class="font-semibold text-n-blue-11">
          {{ verAntigos ? t(`${N}.ESCONDER_ANTIGOS`) : t(`${N}.VER_ANTIGOS`) }}
        </span>
      </button>
    </section>

    <!-- O dia -->
    <section data-secao="dia" class="flex flex-col gap-3">
      <h3
        class="mb-0 flex items-center gap-2 text-lg font-semibold text-n-slate-12"
      >
        <span
          class="size-5 text-n-blue-10"
          :class="ehHoje ? 'i-lucide-sun' : 'i-lucide-calendar-days'"
          aria-hidden="true"
        />
        {{ ehHoje ? t(`${N}.PARA_HOJE`) : nomeDoDia(dia) }}
        <span
          v-if="doDia.length"
          class="rounded-full bg-n-alpha-2 px-2 text-sm font-semibold text-n-slate-11"
        >
          {{ doDia.length }}
        </span>
      </h3>
      <ul v-if="doDia.length" class="m-0 flex list-none flex-col gap-2 p-0">
        <template v-for="(item, indice) in doDia" :key="item.id">
          <li
            v-if="indice === linhaDoAgora"
            data-agora
            class="flex items-center gap-2 py-1 text-xs font-semibold text-n-blue-11"
            aria-hidden="true"
          >
            <span class="size-2 rounded-full bg-n-blue-9" />
            {{ t(`${N}.AGORA`, { hora: horaDeAgora }) }}
            <span class="h-px flex-1 bg-n-blue-7" />
          </li>
          <CalendarioItem v-bind="ligar(item)" v-on="repassar" />
        </template>
        <li
          v-if="linhaDoAgora === doDia.length"
          data-agora
          class="flex items-center gap-2 py-1 text-xs font-semibold text-n-blue-11"
          aria-hidden="true"
        >
          <span class="size-2 rounded-full bg-n-blue-9" />
          {{ t(`${N}.AGORA`, { hora: horaDeAgora }) }}
          <span class="h-px flex-1 bg-n-blue-7" />
        </li>
      </ul>
      <div
        v-else
        data-dia-vazio
        class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-n-slate-6 bg-n-solid-1 px-6 py-10 text-center"
      >
        <span
          class="grid size-14 place-items-center rounded-full"
          :class="
            ehHoje
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          aria-hidden="true"
        >
          <span
            class="size-7"
            :class="ehHoje ? 'i-lucide-party-popper' : 'i-lucide-coffee'"
          />
        </span>
        <p class="mb-0 text-lg font-semibold text-n-slate-12">
          {{
            ehHoje
              ? t(`${N}.VAZIO_HOJE`)
              : t(`${N}.VAZIO_DIA`, { dia: diaNaFrase(dia) })
          }}
        </p>
        <p class="mb-0 max-w-md text-sm text-n-slate-11">
          {{ ehHoje ? linhaDoProximo : t(`${N}.VAZIO_DIA_TEXTO`) }}
        </p>
        <Button
          data-novo-no-dia
          :label="ehHoje ? t(`${N}.NOVO`) : t(`${N}.NOVO_NO_DIA`)"
          icon="i-lucide-plus"
          class="!min-h-11"
          @click="emit('novo', dia)"
        />
      </div>
    </section>

    <!-- Próximos dias -->
    <section
      v-if="proximosDias.length"
      data-secao="proximos"
      class="flex flex-col gap-3"
    >
      <h3
        class="mb-0 flex items-center gap-2 text-lg font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-calendar-range size-5 text-n-slate-10"
          aria-hidden="true"
        />
        {{ t(`${N}.PROXIMOS`) }}
      </h3>
      <div
        v-for="grupo in proximosDias"
        :key="grupo.chave"
        class="flex flex-col gap-2"
      >
        <h4
          class="mb-0 text-sm font-semibold text-n-slate-11 first-letter:uppercase"
        >
          {{ nomeDoDia(grupo.chave) }}
        </h4>
        <ul class="m-0 flex list-none flex-col gap-2 p-0">
          <CalendarioItem
            v-for="item in grupo.lista"
            :key="item.id"
            v-bind="ligar(item)"
            v-on="repassar"
          />
        </ul>
      </div>
    </section>
  </div>
</template>
