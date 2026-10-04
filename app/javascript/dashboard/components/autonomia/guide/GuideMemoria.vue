<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// #933 — "O que eu sei": o que o Guia lembra da pessoa e da corretora. Dá para
// corrigir no lugar e apagar (com confirmação, porque não tem desfazer). Vazio,
// ensina a primeira frase e deixa tocar num exemplo, que vai para o Guia.
const emit = defineEmits(['perguntar']);

const { t } = useI18n();

const TAMANHO = 200;

const memorias = ref({ pessoais: [], corretora: [] });
const podeEditarCorretora = ref(false);
const carregando = ref(true);
const falhou = ref(false);
const editando = ref(null);
const rascunho = ref('');
const salvando = ref(false);
const paraApagar = ref(null);
const apagando = ref(false);
const dialogo = ref(null);

const secoes = computed(() => [
  {
    id: 'pessoais',
    titulo: t('AUTONOMIA_GUIDE.MEMORY.ABOUT_YOU'),
    vazio: t('AUTONOMIA_GUIDE.MEMORY.EMPTY_YOU_TITLE'),
    editavel: true,
    exemplos: [
      t('AUTONOMIA_GUIDE.MEMORY.EXAMPLE_YOU_1'),
      t('AUTONOMIA_GUIDE.MEMORY.EXAMPLE_YOU_2'),
    ],
  },
  {
    id: 'corretora',
    titulo: t('AUTONOMIA_GUIDE.MEMORY.ABOUT_COMPANY'),
    vazio: t('AUTONOMIA_GUIDE.MEMORY.EMPTY_COMPANY_TITLE'),
    editavel: podeEditarCorretora.value,
    exemplos: podeEditarCorretora.value
      ? [
          t('AUTONOMIA_GUIDE.MEMORY.EXAMPLE_COMPANY_1'),
          t('AUTONOMIA_GUIDE.MEMORY.EXAMPLE_COMPANY_2'),
        ]
      : [],
  },
]);

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    const { data } = await AutonomiaGuideAPI.memorias();
    memorias.value = {
      pessoais: data?.pessoais || [],
      corretora: data?.corretora || [],
    };
    podeEditarCorretora.value = data?.pode_editar_corretora === true;
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
};

const trocar = (secao, id, novo) => {
  memorias.value = {
    ...memorias.value,
    [secao]: memorias.value[secao]
      .map(item => (item.id === id ? novo : item))
      .filter(Boolean),
  };
};

const editar = item => {
  editando.value = item.id;
  rascunho.value = item.texto;
};

const cancelar = () => {
  editando.value = null;
  rascunho.value = '';
};

const salvar = async (secao, item) => {
  const texto = rascunho.value.trim();
  if (!texto || salvando.value) return;
  salvando.value = true;
  try {
    const { data } = await AutonomiaGuideAPI.corrigirMemoria(item.id, texto);
    trocar(secao, item.id, { ...item, ...data });
    cancelar();
    useAlert(t('AUTONOMIA_GUIDE.MEMORY.SAVED'));
  } catch {
    useAlert(t('AUTONOMIA_GUIDE.MEMORY.SAVE_FAILED'));
  } finally {
    salvando.value = false;
  }
};

const pedirParaApagar = (secao, item) => {
  paraApagar.value = { secao, item };
  dialogo.value?.open();
};

const apagar = async () => {
  const alvo = paraApagar.value;
  if (!alvo || apagando.value) return;
  apagando.value = true;
  try {
    await AutonomiaGuideAPI.apagarMemoria(alvo.item.id);
    trocar(alvo.secao, alvo.item.id, null);
    dialogo.value?.close();
    useAlert(t('AUTONOMIA_GUIDE.MEMORY.FORGOTTEN'));
  } catch {
    useAlert(t('AUTONOMIA_GUIDE.MEMORY.DELETE_FAILED'));
  } finally {
    apagando.value = false;
  }
};

onMounted(carregar);
</script>

<template>
  <div class="flex flex-col gap-5 w-full">
    <p
      v-if="carregando"
      class="flex items-center gap-2 mb-0 text-n-slate-11"
      role="status"
    >
      <span class="i-svg-spinner size-4 shrink-0" aria-hidden="true" />
      {{ $t('AUTONOMIA_GUIDE.MEMORY.LOADING') }}
    </p>
    <div
      v-else-if="falhou"
      class="flex flex-col items-start gap-2"
      role="alert"
    >
      <p class="mb-0 text-n-ruby-11">
        {{ $t('AUTONOMIA_GUIDE.MEMORY.LOAD_FAILED') }}
      </p>
      <Button
        :label="$t('AUTONOMIA_GUIDE.MEMORY.RETRY')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="min-h-11"
        @click="carregar"
      />
    </div>
    <template v-else-if="!carregando && !falhou">
      <p class="mb-0 text-xs text-n-slate-11">
        {{ $t('AUTONOMIA_GUIDE.MEMORY.KEPT') }}
      </p>
      <section
        v-for="secao in secoes"
        :key="secao.id"
        class="flex flex-col gap-2"
        :data-secao="secao.id"
      >
        <h3 class="mb-0 text-xs font-medium text-n-slate-11">
          {{ secao.titulo }}
        </h3>
        <div
          v-if="!memorias[secao.id].length"
          class="flex flex-col gap-2"
          data-vazio
        >
          <p class="mb-0 font-medium text-n-slate-12">{{ secao.vazio }}</p>
          <p class="mb-0 text-n-slate-11">
            {{ $t('AUTONOMIA_GUIDE.MEMORY.EMPTY_TEXT') }}
          </p>
          <button
            v-for="exemplo in secao.exemplos"
            :key="exemplo"
            type="button"
            data-exemplo
            class="text-left text-sm text-n-slate-12 bg-n-alpha-1 hover:bg-n-alpha-2 rounded-lg px-3 py-2 min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="emit('perguntar', exemplo)"
          >
            {{ exemplo }}
          </button>
        </div>
        <ul v-else class="flex flex-col gap-1 m-0 p-0 list-none">
          <li
            v-for="item in memorias[secao.id]"
            :key="item.id"
            data-memoria
            class="flex items-stretch gap-1 rounded-lg hover:bg-n-alpha-1"
          >
            <form
              v-if="editando === item.id"
              class="flex flex-col flex-1 gap-2 p-2"
              @submit.prevent="salvar(secao.id, item)"
            >
              <TextArea
                :id="`guia-memoria-${item.id}`"
                v-model="rascunho"
                :label="$t('AUTONOMIA_GUIDE.MEMORY.EDIT_LABEL')"
                :max-length="TAMANHO"
                show-character-count
                auto-height
                autofocus
                @keydown.esc.prevent="cancelar"
              />
              <div class="flex flex-wrap gap-2">
                <Button
                  type="submit"
                  :label="$t('AUTONOMIA_GUIDE.MEMORY.SAVE')"
                  :is-loading="salvando"
                  :disabled="!rascunho.trim()"
                  blue
                  class="min-h-11"
                />
                <Button
                  type="button"
                  :label="$t('AUTONOMIA_GUIDE.MEMORY.CANCEL')"
                  slate
                  faded
                  class="min-h-11"
                  @click="cancelar"
                />
              </div>
            </form>
            <template v-else>
              <p
                class="flex flex-col flex-1 justify-center min-w-0 min-h-11 px-3 py-2 mb-0 text-sm text-n-slate-12 break-words"
              >
                {{ item.texto }}
                <span v-if="item.autor" class="text-xs text-n-slate-11">
                  {{
                    $t('AUTONOMIA_GUIDE.MEMORY.TAUGHT_BY', {
                      nome: item.autor,
                    })
                  }}
                </span>
              </p>
              <template v-if="secao.editavel">
                <Button
                  v-tooltip="$t('AUTONOMIA_GUIDE.MEMORY.EDIT')"
                  :aria-label="
                    $t('AUTONOMIA_GUIDE.MEMORY.EDIT_NAMED', {
                      texto: item.texto,
                    })
                  "
                  icon="i-lucide-pencil"
                  ghost
                  slate
                  lg
                  class="shrink-0 self-center"
                  @click="editar(item)"
                />
                <Button
                  v-tooltip="$t('AUTONOMIA_GUIDE.MEMORY.DELETE')"
                  :aria-label="
                    $t('AUTONOMIA_GUIDE.MEMORY.DELETE_NAMED', {
                      texto: item.texto,
                    })
                  "
                  icon="i-lucide-trash-2"
                  ghost
                  slate
                  lg
                  class="shrink-0 self-center"
                  @click="pedirParaApagar(secao.id, item)"
                />
              </template>
            </template>
          </li>
        </ul>
        <p
          v-if="!secao.editavel"
          class="mb-0 text-xs text-n-slate-11"
          data-so-admin
        >
          {{ $t('AUTONOMIA_GUIDE.MEMORY.ONLY_ADMIN') }}
        </p>
      </section>
    </template>

    <Dialog
      ref="dialogo"
      type="alert"
      width="sm"
      :title="$t('AUTONOMIA_GUIDE.MEMORY.CONFIRM_TITLE')"
      :description="$t('AUTONOMIA_GUIDE.MEMORY.CONFIRM_TEXT')"
      :confirm-button-label="$t('AUTONOMIA_GUIDE.MEMORY.CONFIRM')"
      :cancel-button-label="$t('AUTONOMIA_GUIDE.MEMORY.KEEP')"
      :is-loading="apagando"
      @confirm="apagar"
      @close="paraApagar = null"
    />
  </div>
</template>
