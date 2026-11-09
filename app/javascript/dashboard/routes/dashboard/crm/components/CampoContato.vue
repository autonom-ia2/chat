<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import ContactAPI from 'dashboard/api/contacts';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Decisão 16 (ex. 11) — campo do card do tipo "contato": busca um contato da
// conta pelo nome, telefone ou e-mail e guarda o id dele ("indicado por
// Maria"). O card confere que o contato é da conta (Crm::CardCampoContato).
// Sem `editavel`, só mostra o nome.
const props = defineProps({
  attribute: { type: Object, required: true },
  editavel: { type: Boolean, default: true },
});

const emit = defineEmits(['update', 'delete']);
const { t } = useI18n();

const MINIMO_DA_BUSCA = 2;
const ESPERA_DA_BUSCA_MS = 300;
const C = 'CRM_KANBAN.DRAWER.CARD_FIELDS';

const idGuardado = computed(() => {
  const id = Number(props.attribute.value);
  return Number.isInteger(id) && id > 0 ? id : null;
});

const opcaoDe = contato => ({
  value: contato.id,
  label: contato.name || `#${contato.id}`,
  hint: contato.phone_number || contato.email || undefined,
});

// O contato guardado, lido pelo id para mostrar o nome.
const atual = ref(null);
const sumiu = ref(false);
watch(
  idGuardado,
  async id => {
    sumiu.value = false;
    if (!id || atual.value?.value === id) return;
    try {
      const { data } = await ContactAPI.show(id);
      atual.value = opcaoDe(data.payload);
    } catch {
      atual.value = null;
      sumiu.value = true;
    }
  },
  { immediate: true }
);

const termo = ref('');
const achados = ref([]);
const buscando = ref(false);
const buscar = useDebounceFn(async texto => {
  try {
    const { data } = await ContactAPI.search(texto, 1, 'name');
    if (termo.value.trim() === texto) achados.value = data.payload || [];
  } catch {
    achados.value = [];
  } finally {
    buscando.value = false;
  }
}, ESPERA_DA_BUSCA_MS);
watch(termo, valor => {
  const texto = valor.trim();
  if (texto.length < MINIMO_DA_BUSCA) {
    achados.value = [];
    return;
  }
  buscando.value = true;
  buscar(texto);
});

const opcoes = computed(() => {
  const lista = achados.value.map(opcaoDe);
  const guardado = atual.value?.value === idGuardado.value && atual.value;
  return guardado && !lista.some(opcao => opcao.value === guardado.value)
    ? [guardado, ...lista]
    : lista;
});
const nome = computed(() => {
  if (!idGuardado.value) return t('CRM_KANBAN.RELATIONSHIP.NOT_INFORMED');
  if (sumiu.value) return t(`${C}.CONTATO_SUMIU`);
  return atual.value?.label || '';
});

const escolhido = computed({
  get: () => idGuardado.value ?? '',
  set: id => {
    atual.value = opcoes.value.find(opcao => opcao.value === id) || null;
    termo.value = '';
    emit('update', id);
  },
});
</script>

<template>
  <span
    v-if="!editavel"
    class="break-words text-sm text-n-slate-12"
    data-campo-contato
  >
    {{ nome }}
  </span>
  <div v-else class="flex flex-col w-full min-w-0 gap-2" data-campo-contato>
    <Input
      v-model="termo"
      type="search"
      size="sm"
      custom-input-class="!h-11"
      :aria-label="
        t(`${C}.BUSCAR_CONTATO`, { campo: attribute.attributeDisplayName })
      "
      :placeholder="t(`${C}.BUSCAR_CONTATO_DICA`)"
      data-busca-contato
    />
    <div class="flex items-center w-full min-w-0 gap-2">
      <ChoiceSelect
        v-model="escolhido"
        :options="opcoes"
        :aria-label="attribute.attributeDisplayName"
        :placeholder="
          sumiu ? t(`${C}.CONTATO_SUMIU`) : t(`${C}.ESCOLHER_CONTATO`)
        "
        class="flex-1 min-w-0"
      />
      <Button
        v-if="idGuardado"
        variant="faded"
        color="ruby"
        icon="i-lucide-trash"
        size="xs"
        class="flex-shrink-0 opacity-0 group-hover/attribute:opacity-100 focus-visible:opacity-100 hover:no-underline"
        :aria-label="t(`${C}.LIMPAR_CONTATO`)"
        @click="emit('delete')"
      />
    </div>
    <p
      v-if="
        termo.trim().length >= MINIMO_DA_BUSCA && !buscando && !achados.length
      "
      class="mb-0 text-xs text-n-slate-11"
      data-sem-contato
    >
      {{ t(`${C}.NENHUM_CONTATO`) }}
    </p>
  </div>
</template>
