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

// O contato guardado, lido pelo id para mostrar o nome. Só o 404 é "apagado";
// outra falha (rede, servidor) diz que não deu para ler agora. A resposta de um
// id antigo, que chega depois da troca, é descartada.
const NAO_ACHADO = 404;
const atual = ref(null);
const leitura = ref('ok');
watch(
  idGuardado,
  async id => {
    leitura.value = 'ok';
    if (!id || atual.value?.value === id) return;
    try {
      const { data } = await ContactAPI.show(id);
      if (idGuardado.value !== id) return;
      atual.value = opcaoDe(data.payload);
    } catch (erro) {
      if (idGuardado.value !== id) return;
      atual.value = null;
      leitura.value =
        erro?.response?.status === NAO_ACHADO ? 'sumiu' : 'falhou';
    }
  },
  { immediate: true }
);
const AVISO_DA_LEITURA = {
  sumiu: `${C}.CONTATO_SUMIU`,
  falhou: `${C}.CONTATO_NAO_CARREGOU`,
};
const avisoDaLeitura = computed(() => {
  const chave = AVISO_DA_LEITURA[leitura.value];
  return chave ? t(chave) : '';
});

const termo = ref('');
const achados = ref([]);
const buscando = ref(false);
// A busca que falhou não é "nenhum contato": diz que não deu para buscar.
const buscaFalhou = ref(false);
const buscar = useDebounceFn(async texto => {
  try {
    const { data } = await ContactAPI.search(texto, 1, 'name');
    if (termo.value.trim() !== texto) return;
    achados.value = data.payload || [];
    buscaFalhou.value = false;
  } catch {
    if (termo.value.trim() !== texto) return;
    achados.value = [];
    buscaFalhou.value = true;
  } finally {
    buscando.value = false;
  }
}, ESPERA_DA_BUSCA_MS);
watch(termo, valor => {
  const texto = valor.trim();
  buscaFalhou.value = false;
  if (texto.length < MINIMO_DA_BUSCA) {
    achados.value = [];
    return;
  }
  buscando.value = true;
  buscar(texto);
});
const semAchados = computed(
  () =>
    termo.value.trim().length >= MINIMO_DA_BUSCA &&
    !buscando.value &&
    !buscaFalhou.value &&
    !achados.value.length
);

const opcoes = computed(() => {
  const lista = achados.value.map(opcaoDe);
  const guardado = atual.value?.value === idGuardado.value && atual.value;
  return guardado && !lista.some(opcao => opcao.value === guardado.value)
    ? [guardado, ...lista]
    : lista;
});
const nome = computed(() => {
  if (!idGuardado.value) return t('CRM_KANBAN.RELATIONSHIP.NOT_INFORMED');
  return avisoDaLeitura.value || atual.value?.label || '';
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
        :placeholder="avisoDaLeitura || t(`${C}.ESCOLHER_CONTATO`)"
        class="flex-1 min-w-0"
      />
      <Button
        v-if="idGuardado"
        variant="faded"
        color="ruby"
        icon="i-lucide-trash"
        size="sm"
        class="flex-shrink-0 !size-11 opacity-0 group-hover/attribute:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-100 hover:no-underline"
        :aria-label="t(`${C}.LIMPAR_CONTATO`)"
        @click="emit('delete')"
      />
    </div>
    <p v-if="semAchados" class="mb-0 text-xs text-n-slate-11" data-sem-contato>
      {{ t(`${C}.NENHUM_CONTATO`) }}
    </p>
    <p
      v-if="buscaFalhou"
      class="mb-0 text-xs text-n-ruby-11"
      role="alert"
      data-busca-falhou
    >
      {{ t(`${C}.BUSCA_FALHOU`) }}
    </p>
  </div>
</template>
