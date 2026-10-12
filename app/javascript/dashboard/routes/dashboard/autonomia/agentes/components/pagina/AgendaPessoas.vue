<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// #1370 — com quem o agente pode marcar, quando a página tem mais de uma pessoa (#1307). "Todas as
// pessoas" vem primeiro e marca ou desmarca todas (fica "meio marcada" quando só algumas estão).
// Cada pessoa é um cartão de 44 px com foto, nome e o selo "agenda pausada". O contrato não muda: a
// gaveta grava [] com todas marcadas. `marcadas` são os ids; o evento devolve a lista nova na ordem
// da página.
const props = defineProps({
  pessoas: { type: Array, required: true },
  marcadas: { type: Array, required: true },
  nome: { type: String, required: true },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['update:marcadas']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.GAVETA_AGENDA.PESSOAS';
const erroId = `pessoas-${useId()}-erro`;

const ids = computed(() => props.pessoas.map(({ id }) => id));
const todas = computed(() =>
  ids.value.every(id => props.marcadas.includes(id))
);
const algumas = computed(() => !todas.value && props.marcadas.length > 0);
const nenhuma = computed(() => !props.marcadas.length);

const marcarTodas = marcada =>
  emit('update:marcadas', marcada ? ids.value : []);
const marcar = (id, marcada) =>
  emit(
    'update:marcadas',
    ids.value.filter(i => (i === id ? marcada : props.marcadas.includes(i)))
  );

const CARTAO =
  'flex items-center gap-3 px-4 py-3 rounded-2xl cursor-pointer min-h-11 ring-1 ring-inset transition bg-n-solid-1 ring-n-weak hover:ring-n-blue-7 has-[:checked]:ring-2 has-[:checked]:ring-n-blue-9 has-[:checked]:bg-n-blue-2 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand';
</script>

<template>
  <fieldset
    data-pessoas
    class="flex flex-col gap-3 p-0 m-0 border-0 min-w-0"
    :disabled="desabilitado"
    :aria-describedby="nenhuma ? erroId : undefined"
  >
    <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.TITULO`, { nome }) }}
    </legend>
    <label data-todas :class="CARTAO">
      <Checkbox
        :model-value="todas"
        :indeterminate="algumas"
        :disabled="desabilitado"
        @update:model-value="marcarTodas"
      />
      <span
        class="grid rounded-full place-items-center size-9 shrink-0 bg-n-alpha-2"
        aria-hidden="true"
      >
        <span class="i-lucide-users size-5 text-n-slate-11" />
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.TODAS`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t(`${NS}.TODAS_DICA`) }}
        </span>
      </span>
    </label>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li v-for="pessoa in pessoas" :key="pessoa.id">
        <label :data-pessoa="pessoa.id" :class="CARTAO">
          <Checkbox
            :model-value="marcadas.includes(pessoa.id)"
            :disabled="desabilitado"
            @update:model-value="marcada => marcar(pessoa.id, marcada)"
          />
          <Avatar :name="pessoa.nome" :size="36" rounded-full />
          <!-- No celular o selo desce para baixo do nome: o nome nunca é cortado. -->
          <span
            class="flex flex-col items-start flex-1 min-w-0 gap-1 sm:flex-row sm:items-center sm:justify-between"
          >
            <span class="text-base text-n-slate-12 [overflow-wrap:anywhere]">
              {{ pessoa.nome }}
            </span>
            <span
              v-if="pessoa.ai_status === 'agenda_pausada'"
              data-pessoa-pausada
              class="inline-flex items-center gap-1 px-2.5 py-0.5 text-sm font-semibold rounded-full shrink-0 bg-n-amber-3 text-n-amber-11"
            >
              <span class="i-lucide-pause size-3.5" aria-hidden="true" />
              {{ t(`${NS}.PAUSADA`) }}
            </span>
          </span>
        </label>
      </li>
    </ul>
    <p
      v-if="nenhuma"
      :id="erroId"
      data-pessoas-erro
      role="alert"
      class="flex items-center gap-2 m-0 text-sm text-n-ruby-11"
    >
      <span class="i-lucide-circle-alert size-4 shrink-0" aria-hidden="true" />
      {{ t(`${NS}.NENHUMA`) }}
    </p>
  </fieldset>
</template>
