<script setup>
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2379 — "Mais → Listas guardadas": as mesmas visualizações salvas da Lista de
// sempre (crm/saved_views). Abrir aplica filtros, "Organizar por" e "Escolher o
// que aparece"; guardar grava a lista como está agora. Mudar quem vê e apagar
// só para quem criou a lista ou para o administrador (Crm::SavedViewPolicy).
const props = defineProps({
  listas: { type: Array, default: () => [] },
  meuId: { type: [Number, String], default: null },
  ehAdmin: { type: Boolean, default: false },
});
const emit = defineEmits(['abrir', 'guardar', 'mudar', 'apagar']);

const { t } = useI18n();
const L = 'CRM_LISTA_ACAO.LISTAS';
const dialogo = useTemplateRef('dialogo');
const campoNome = useTemplateRef('campoNome');
const raiz = useTemplateRef('raiz');
const nome = ref('');
const quemVe = ref('private_view');
const apagando = ref(null);

const opcoesDeQuemVe = computed(() => [
  { value: 'private_view', label: t(`${L}.QUEM_VE.SO_EU`) },
  { value: 'team', label: t(`${L}.QUEM_VE.EQUIPE`) },
  { value: 'account', label: t(`${L}.QUEM_VE.TODOS`) },
]);
const rotuloDeQuemVe = valor =>
  opcoesDeQuemVe.value.find(opcao => opcao.value === valor)?.label || '';
const podeMexer = lista =>
  props.ehAdmin || String(lista.user_id) === String(props.meuId);

const abrir = () => {
  nome.value = '';
  quemVe.value = 'private_view';
  apagando.value = null;
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

const abrirLista = lista => {
  emit('abrir', lista);
  fechar();
};
const guardar = () => {
  const limpo = nome.value.trim();
  if (!limpo) {
    campoNome.value?.focus();
    return;
  }
  emit('guardar', { name: limpo, visibility: quemVe.value });
  nome.value = '';
};
const mudarQuemVe = (lista, valor) => {
  if (valor && valor !== lista.visibility)
    emit('mudar', { id: lista.id, visibility: valor });
};
const pedirApagar = async lista => {
  apagando.value = lista.id;
  await nextTick();
  raiz.value?.querySelector('[data-lista-confirmar]')?.focus();
};
const confirmarApagar = lista => {
  emit('apagar', { id: lista.id });
  apagando.value = null;
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="lg"
    :title="t(`${L}.TITULO`)"
    :show-confirm-button="false"
    :cancel-button-label="t(`${L}.FECHAR`)"
    overflow-y-auto
  >
    <div ref="raiz" class="flex flex-col gap-5" data-lista-acao-listas>
      <p v-if="!listas.length" class="mb-0 text-base text-n-slate-11">
        {{ t(`${L}.NENHUMA`) }}
      </p>
      <ul v-else class="-mx-2 mb-0 flex flex-col gap-1">
        <li
          v-for="lista in listas"
          :key="lista.id"
          :data-lista-guardada="lista.id"
          class="flex flex-wrap items-center gap-2 rounded-xl px-2 py-1 hover:bg-n-alpha-2"
        >
          <template v-if="apagando === lista.id">
            <p class="mb-0 min-w-0 flex-1 text-base text-n-slate-12">
              {{ t(`${L}.APAGAR_PERGUNTA`, { nome: lista.name }) }}
            </p>
            <Button
              :label="t(`${L}.APAGAR_SIM`)"
              ruby
              data-lista-confirmar
              type="button"
              class="!h-11 !rounded-xl !px-4 !text-base"
              @click="confirmarApagar(lista)"
            />
            <Button
              :label="t(`${L}.APAGAR_NAO`)"
              slate
              outline
              type="button"
              class="!h-11 !rounded-xl !px-4 !text-base"
              @click="apagando = null"
            />
          </template>
          <template v-else>
            <button
              type="button"
              data-lista-abrir
              class="flex min-h-11 w-full min-w-0 items-center gap-3 rounded-xl px-2 text-start text-base font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand sm:w-auto sm:flex-1"
              :aria-label="t(`${L}.ABRIR`, { nome: lista.name })"
              @click="abrirLista(lista)"
            >
              <span
                class="i-lucide-bookmark size-5 shrink-0 text-n-slate-11"
                aria-hidden="true"
              />
              <span class="min-w-0 break-words">{{ lista.name }}</span>
            </button>
            <!-- No celular, quem vê e apagar vão para a linha de baixo: o nome
                 da lista aparece inteiro. -->
            <span
              v-if="podeMexer(lista)"
              class="ms-auto flex items-center gap-2 ps-10 sm:ps-0"
            >
              <ChoiceSelect
                :model-value="lista.visibility"
                :options="opcoesDeQuemVe"
                :aria-label="t(`${L}.QUEM_VE.ROTULO_DA`, { nome: lista.name })"
                compact
                class="[&>button]:!h-11 [&>button]:!rounded-xl"
                @update:model-value="valor => mudarQuemVe(lista, valor)"
              />
              <button
                type="button"
                data-lista-apagar
                :aria-label="t(`${L}.APAGAR`, { nome: lista.name })"
                class="grid size-11 place-items-center rounded-xl text-n-ruby-11 hover:bg-n-ruby-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                @click="pedirApagar(lista)"
              >
                <span class="i-lucide-trash-2 size-5" aria-hidden="true" />
              </button>
            </span>
            <span v-else class="px-2 text-sm text-n-slate-11">
              {{ rotuloDeQuemVe(lista.visibility) }}
            </span>
          </template>
        </li>
      </ul>

      <div
        class="flex flex-col gap-3 border-t border-n-weak pt-4"
        data-lista-acao-guardar
      >
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t(`${L}.GUARDAR_TITULO`) }}
        </p>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">{{ t(`${L}.NOME`) }}</span>
          <input
            ref="campoNome"
            v-model="nome"
            type="text"
            maxlength="80"
            :placeholder="t(`${L}.NOME_EXEMPLO`)"
            class="reset-base !mb-0 min-h-11 w-full rounded-xl border border-solid border-n-weak bg-n-solid-1 px-3 text-base text-n-slate-12 placeholder:text-n-slate-11 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @keydown.enter.prevent="guardar"
          />
        </label>
        <div class="flex flex-wrap items-end gap-3">
          <div class="flex min-w-48 flex-1 flex-col gap-1">
            <span class="text-sm text-n-slate-11">
              {{ t(`${L}.QUEM_VE.TITULO`) }}
            </span>
            <ChoiceSelect
              v-model="quemVe"
              :options="opcoesDeQuemVe"
              :aria-label="t(`${L}.QUEM_VE.TITULO`)"
              class="w-full [&>button]:!h-11 [&>button]:!w-full [&>button]:!rounded-xl"
            />
          </div>
          <Button
            :label="t(`${L}.GUARDAR`)"
            type="button"
            data-lista-guardar
            class="!h-11 !rounded-xl !px-5 !text-base !font-semibold"
            @click="guardar"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
