<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #1462 — quem recebe o aviso. Com card, o padrão é "quem cuida do cliente",
// que acompanha a troca de dono. Pessoas sem acesso ao funil do card aparecem
// desligadas, com o motivo (a mesma regra do "Quem cuida", owner_options).
const props = defineProps({
  // { id, name } de quem cuida do cliente; null sem card.
  dono: { type: Object, default: null },
  eu: { type: Object, required: true },
  agentes: { type: Array, default: () => [] },
  // ids de quem não vê o funil do card.
  barrados: { type: Array, default: () => [] },
  funil: { type: String, default: '' },
  times: { type: Array, default: () => [] },
  // { [timeId]: ['Paula Nunes', …] }
  membros: { type: Object, default: () => ({}) },
});
const quem = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const Q = 'CRM_LEMBRETE.QUEM';
const id = useId();

const opcoes = computed(() =>
  [
    props.dono && {
      tipo: 'dono',
      icone: 'i-lucide-user-check',
      titulo: t(`${Q}.DONO`),
      texto: t(`${Q}.DONO_TEXTO`, { nome: props.dono.name }),
    },
    {
      tipo: 'eu',
      icone: 'i-lucide-user-round',
      titulo: t(`${Q}.EU`),
      texto: t(`${Q}.EU_TEXTO`, { nome: props.eu.name }),
    },
    {
      tipo: 'pessoas',
      icone: 'i-lucide-users',
      titulo: t(`${Q}.PESSOAS`),
      texto: t(`${Q}.PESSOAS_TEXTO`),
    },
    {
      tipo: 'time',
      icone: 'i-lucide-users-round',
      titulo: t(`${Q}.TIME`),
      texto: t(`${Q}.TIME_TEXTO`),
    },
  ].filter(Boolean)
);

const escolher = tipo => {
  quem.value = { ...quem.value, tipo };
};
const alternar = pessoaId => {
  const lista = quem.value.pessoas.includes(pessoaId)
    ? quem.value.pessoas.filter(item => item !== pessoaId)
    : [...quem.value.pessoas, pessoaId];
  quem.value = { ...quem.value, pessoas: lista };
};
const opcoesDeTime = computed(() =>
  props.times.map(time => ({
    value: time.id,
    label: t(`${Q}.TIME_NOME`, {
      nome: time.name,
      n: (props.membros[time.id] || []).length,
    }),
  }))
);
const membrosDoTime = computed(() => props.membros[quem.value.time] || []);
const juntar = nomes =>
  new Intl.ListFormat(locale.value.replace('_', '-'), {
    style: 'long',
    type: 'conjunction',
  }).format(nomes);
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-3 border-0 p-0" data-quem-recebe>
    <legend class="mb-1 p-0 text-base font-semibold text-n-slate-12">
      {{ t(`${Q}.PERGUNTA`) }}
    </legend>
    <div class="grid gap-2 sm:grid-cols-2">
      <button
        v-for="opcao in opcoes"
        :key="opcao.tipo"
        type="button"
        :data-quem="opcao.tipo"
        :aria-pressed="quem.tipo === opcao.tipo"
        class="flex min-h-11 items-start gap-3 rounded-2xl p-4 text-start ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          quem.tipo === opcao.tipo
            ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
            : 'bg-n-solid-1 ring-n-weak hover:ring-n-slate-7'
        "
        @click="escolher(opcao.tipo)"
      >
        <span
          class="mt-0.5 size-5 shrink-0 text-n-blue-11"
          :class="opcao.icone"
          aria-hidden="true"
        />
        <span class="flex min-w-0 flex-col gap-1">
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">
            {{ opcao.titulo }}
          </span>
          <span class="text-sm text-n-slate-11">{{ opcao.texto }}</span>
        </span>
      </button>
    </div>

    <div
      v-if="quem.tipo === 'pessoas'"
      class="flex flex-col gap-2"
      data-quem-pessoas
    >
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t(`${Q}.ESCOLHA_PESSOAS`) }}
      </p>
      <ul class="m-0 grid list-none gap-2 p-0 sm:grid-cols-2">
        <li v-for="agente in agentes" :key="agente.id">
          <button
            type="button"
            :aria-pressed="quem.pessoas.includes(agente.id)"
            :disabled="barrados.includes(agente.id)"
            class="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed disabled:opacity-60"
            :class="
              quem.pessoas.includes(agente.id)
                ? 'bg-n-blue-2 ring-n-blue-8'
                : 'bg-n-solid-1 ring-n-weak hover:ring-n-slate-7'
            "
            @click="alternar(agente.id)"
          >
            <Avatar :name="agente.name" :src="agente.thumbnail" :size="28" />
            <span class="flex min-w-0 flex-1 flex-col">
              <span class="truncate text-sm font-medium text-n-slate-12">
                {{ agente.name }}
              </span>
              <span
                v-if="barrados.includes(agente.id)"
                class="text-xs text-n-slate-11"
              >
                {{ t(`${Q}.SEM_FUNIL`, { funil }) }}
              </span>
            </span>
            <span
              class="grid size-5 shrink-0 place-items-center rounded-md ring-1 ring-inset"
              :class="
                quem.pessoas.includes(agente.id)
                  ? 'bg-n-blue-9 text-white ring-n-blue-9'
                  : 'ring-n-slate-7'
              "
              aria-hidden="true"
            >
              <span
                v-if="quem.pessoas.includes(agente.id)"
                class="i-lucide-check size-3.5"
              />
            </span>
          </button>
        </li>
      </ul>
    </div>

    <div
      v-if="quem.tipo === 'time'"
      class="flex max-w-[22rem] flex-col gap-2"
      data-quem-time
    >
      <label :for="`${id}-time`" class="text-sm font-medium text-n-slate-12">
        {{ t(`${Q}.QUAL_TIME`) }}
      </label>
      <ChoiceSelect
        :model-value="quem.time"
        :trigger-id="`${id}-time`"
        :options="opcoesDeTime"
        :placeholder="t(`${Q}.ESCOLHA_TIME`)"
        :aria-label="t(`${Q}.QUAL_TIME`)"
        class="w-full"
        @update:model-value="valor => (quem = { ...quem, time: valor })"
      />
      <p v-if="membrosDoTime.length" class="mb-0 text-sm text-n-slate-11">
        {{ t(`${Q}.RECEBEM`, { nomes: juntar(membrosDoTime) }) }}
      </p>
    </div>

    <p
      v-if="quem.tipo !== 'eu'"
      class="mb-0 flex items-start gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-eye mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ t(`${Q}.CRIADOR_VE`) }}
    </p>
  </fieldset>
</template>
