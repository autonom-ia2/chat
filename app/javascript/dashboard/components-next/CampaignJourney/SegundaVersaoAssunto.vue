<script setup>
// #3099 — no e-mail, a versão 2 é outro assunto; o conteúdo do e-mail é o mesmo nas duas. Os assuntos que a IA já
// sugere quando cria o e-mail (hoje a pessoa escolhe um e descarta os outros) viram ideias de um toque. Ao lado, as
// duas versões como linhas da caixa de entrada do cliente.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  assunto: { type: String, default: '' },
  primeira: { type: String, default: '' },
  sugestoes: { type: Array, default: () => [] },
  remetente: { type: String, default: '' },
  previa: { type: String, default: '' },
});
const emit = defineEmits(['update']);

const NS = 'DUAS_VERSOES.ASSUNTO';
const { t } = useI18n();

const ideias = computed(() =>
  props.sugestoes
    .map(ideia => String(ideia).trim())
    .filter(ideia => ideia && ideia !== props.primeira.trim())
);
const versoes = computed(() => [
  { numero: 1, assunto: props.primeira },
  { numero: 2, assunto: props.assunto },
]);
</script>

<template>
  <div
    class="grid grid-cols-[minmax(0,1fr)] gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start"
    data-segunda-versao-assunto
  >
    <div class="flex min-w-0 flex-col gap-3">
      <Input
        :model-value="assunto"
        :label="t(`${NS}.ROTULO`)"
        :placeholder="t(`${NS}.PLACEHOLDER`)"
        custom-input-class="!h-11"
        data-assunto-da-2
        @update:model-value="valor => emit('update', valor)"
      />
      <div v-if="ideias.length" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          <span
            class="i-lucide-sparkles me-1 size-3.5 align-[-2px]"
            aria-hidden="true"
          />
          {{ t(`${NS}.IDEIAS`) }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="ideia in ideias"
            :key="ideia"
            type="button"
            class="min-h-11 rounded-xl px-3 text-start ring-1 ring-inset text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              assunto === ideia
                ? 'bg-n-blue-2 text-n-blue-11 ring-n-blue-8'
                : 'bg-n-solid-1 text-n-slate-12 ring-n-slate-7 hover:bg-n-alpha-1'
            "
            :aria-pressed="assunto === ideia"
            :aria-label="t(`${NS}.USAR_IDEIA`, { assunto: ideia })"
            data-ideia-de-assunto
            @click="emit('update', ideia)"
          >
            {{ ideia }}
          </button>
        </div>
      </div>
    </div>

    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
      data-como-chega
    >
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.COMO_FICA`) }}
      </h3>
      <ul
        class="m-0 flex list-none flex-col divide-y divide-n-weak overflow-hidden rounded-xl bg-n-solid-1 p-0"
      >
        <li
          v-for="versao in versoes"
          :key="versao.numero"
          class="flex flex-col gap-0.5 px-3 py-2.5"
          :data-previa-versao="versao.numero"
        >
          <span class="text-xs font-semibold text-n-slate-11">
            {{ t('DUAS_VERSOES.MENSAGEM.VERSAO', { n: versao.numero }) }}
          </span>
          <strong class="truncate text-sm text-n-slate-12">
            {{ remetente }}
          </strong>
          <span
            class="truncate text-sm"
            :class="versao.assunto ? 'text-n-slate-12' : 'text-n-slate-10'"
          >
            {{ versao.assunto || t(`${NS}.SEM_ASSUNTO`) }}
          </span>
          <span v-if="previa" class="truncate text-xs text-n-slate-11">
            {{ previa }}
          </span>
        </li>
      </ul>
    </aside>
  </div>
</template>
