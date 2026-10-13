<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { quemComParteFora } from '../passagem';

// #1385 — quem recebe quando parte da equipe está fora: as pessoas com o ponto de online e uma frase com o fato. Sai
// do que o seletor faz de verdade (HandoffMemberSelector prefere quem está online; a regra antiga não olha isso).
const props = defineProps({
  regra: { type: Object, required: true },
  fila: { type: Array, default: () => [] },
  pessoa: { type: String, default: '' },
});

const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';

const fato = computed(() =>
  quemComParteFora({
    regra: props.regra,
    fila: props.fila,
    pessoa: props.pessoa,
  })
);
const pessoas = computed(() => {
  if (!fato.value.fora) return [];
  return [
    { nome: fato.value.fora, online: false },
    { nome: fato.value.online, online: true },
  ];
});
const texto = computed(() => t(`${P}.ONLINE.${fato.value.chave}`, fato.value));
</script>

<template>
  <section
    data-previa-online
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${P}.ONLINE_TITULO`) }}
    </h3>
    <ul v-if="pessoas.length" class="m-0 flex list-none flex-wrap gap-2 p-0">
      <li
        v-for="item in pessoas"
        :key="item.nome"
        class="inline-flex items-center gap-2 rounded-full bg-n-alpha-2 py-1 pe-3 ps-2 text-sm text-n-slate-12"
      >
        <span
          class="size-2.5 rounded-full"
          :class="item.online ? 'bg-n-teal-9' : 'bg-n-slate-7'"
          aria-hidden="true"
        />
        {{ item.nome }}
        <span class="text-n-slate-11">
          {{ t(`${P}.ONLINE.${item.online ? 'ONLINE' : 'FORA'}`) }}
        </span>
      </li>
    </ul>
    <p
      class="mb-0 flex items-start gap-2 rounded-xl px-3 py-2 text-sm text-n-slate-12"
      :class="
        fato.chave === 'EQUIPE_ANTIGA' || fato.chave === 'PESSOA_FORA'
          ? 'bg-n-amber-2'
          : 'bg-n-blue-2'
      "
    >
      <span
        class="i-lucide-user-round-check mt-0.5 size-4 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ texto }}
    </p>
  </section>
</template>
