<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ContactAPI from 'dashboard/api/contacts';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #1461 — "É sobre quem?". O lembrete pode ficar só no calendário (pagar o
// aluguel), ser de um cliente sem negócio aberto (aniversário) ou de um
// negócio do funil (aí ele aparece também no card). As buscas são as reais.
const emit = defineEmits(['card']);
const ligadoA = defineModel({ type: Object, required: true });

const { t } = useI18n();
const L = 'CRM_LEMBRETE.LIGAR';
const OPCOES = [
  { tipo: 'nada', icone: 'i-lucide-calendar', chave: 'NADA' },
  { tipo: 'contato', icone: 'i-lucide-contact-round', chave: 'CONTATO' },
  { tipo: 'card', icone: 'i-lucide-briefcase-business', chave: 'CARD' },
];

const opcoes = ref([]);
let busca = 0;
const buscar = async termo => {
  const texto = (termo || '').trim();
  if (texto.length < 2) {
    opcoes.value = [];
    return;
  }
  busca += 1;
  const minha = busca;
  try {
    const lista =
      ligadoA.value.tipo === 'contato'
        ? (await ContactAPI.search(texto)).data?.payload || []
        : (await CrmKanbanAPI.getCards({ search: texto, per_page: 8 })).data
            ?.payload || [];
    if (minha !== busca) return;
    opcoes.value = lista.map(item => ({
      value: item.id,
      label:
        ligadoA.value.tipo === 'contato'
          ? item.name
          : [item.contact?.name, item.title].filter(Boolean).join(' · '),
    }));
  } catch {
    opcoes.value = [];
  }
};
const escolherTipo = tipo => {
  opcoes.value = [];
  ligadoA.value = { tipo };
  emit('card', null);
};
const escolher = valor => {
  const achado = opcoes.value.find(item => item.value === valor);
  const nome = achado?.label || '';
  if (ligadoA.value.tipo === 'card') {
    ligadoA.value = { tipo: 'card', cardId: valor, nome };
    emit('card', valor);
    return;
  }
  ligadoA.value = { tipo: 'contato', contatoId: valor, nome };
};
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-3 border-0 p-0" data-ligar-a>
    <legend class="mb-1 p-0 text-base font-semibold text-n-slate-12">
      {{ t(`${L}.PERGUNTA`) }}
    </legend>
    <div class="grid gap-2 sm:grid-cols-3">
      <button
        v-for="opcao in OPCOES"
        :key="opcao.tipo"
        type="button"
        :data-ligar="opcao.tipo"
        :aria-pressed="ligadoA.tipo === opcao.tipo"
        class="flex min-h-11 flex-col items-start gap-1.5 rounded-2xl p-4 text-start ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          ligadoA.tipo === opcao.tipo
            ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
            : 'bg-n-solid-1 ring-n-weak hover:ring-n-slate-7'
        "
        @click="escolherTipo(opcao.tipo)"
      >
        <span
          class="size-5 text-n-blue-11"
          :class="opcao.icone"
          aria-hidden="true"
        />
        <span class="text-[0.9375rem] font-semibold text-n-slate-12">
          {{ t(`${L}.${opcao.chave}`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t(`${L}.${opcao.chave}_TEXTO`) }}
        </span>
      </button>
    </div>
    <div
      v-if="ligadoA.tipo !== 'nada'"
      class="flex max-w-[28rem] flex-col gap-1"
      data-ligar-busca
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{
          t(`${L}.${ligadoA.tipo === 'card' ? 'QUAL_CARD' : 'QUAL_CONTATO'}`)
        }}
      </span>
      <ComboBox
        :key="ligadoA.tipo"
        :model-value="ligadoA.cardId || ligadoA.contatoId || ''"
        :options="opcoes"
        :display-label="ligadoA.nome || ''"
        use-api-results
        :placeholder="t(`${L}.BUSCAR`)"
        :search-placeholder="t(`${L}.BUSCAR_DICA`)"
        @update:model-value="escolher"
        @search="buscar"
      />
    </div>
  </fieldset>
</template>
