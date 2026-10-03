<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// #861 — as conversas anteriores com o Guia. Tocar numa abre e continua de
// onde parou; apagar pede confirmação, porque não tem desfazer.
const props = defineProps({
  // A conversa aberta no painel agora, para marcar na lista.
  conversaAtual: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['abrir', 'apagou']);

const { t, locale } = useI18n();

// O servidor diz quantos dias guarda; este é só o valor até a resposta chegar.
const RETENCAO_PADRAO = 30;
const POR_PAGINA = 20;
const DIA_MS = 24 * 60 * 60 * 1000;

const conversas = ref([]);
const retencao = ref(RETENCAO_PADRAO);
const carregando = ref(true);
const falhou = ref(false);
const pagina = ref(1);
const temMais = ref(false);
const carregandoMais = ref(false);
const paraApagar = ref(null);
const apagando = ref(false);
const dialogo = ref(null);

const vazia = computed(
  () => !carregando.value && !falhou.value && !conversas.value.length
);

// "hoje", "ontem", "há 3 dias" — no idioma de quem está olhando.
const haQuanto = iso => {
  const dias = Math.floor((Date.now() - new Date(iso).getTime()) / DIA_MS);
  return new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' }).format(
    -Math.max(dias, 0),
    'day'
  );
};

const buscar = async numero => {
  const { data } = await AutonomiaGuideAPI.conversas(numero);
  const lista = data?.conversas || [];
  retencao.value = data?.retencao_dias || RETENCAO_PADRAO;
  temMais.value = lista.length === POR_PAGINA;
  pagina.value = numero;
  return lista;
};

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    conversas.value = await buscar(1);
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
};

const verMais = async () => {
  carregandoMais.value = true;
  try {
    conversas.value = [...conversas.value, ...(await buscar(pagina.value + 1))];
  } catch {
    useAlert(t('AUTONOMIA_GUIDE.HISTORY.LOAD_FAILED'));
  } finally {
    carregandoMais.value = false;
  }
};

const pedirParaApagar = conversa => {
  paraApagar.value = conversa;
  dialogo.value?.open();
};

const apagar = async () => {
  const conversa = paraApagar.value;
  if (!conversa || apagando.value) return;
  apagando.value = true;
  try {
    await AutonomiaGuideAPI.apagarConversa(conversa.id);
    conversas.value = conversas.value.filter(item => item.id !== conversa.id);
    emit('apagou', conversa.id);
    dialogo.value?.close();
  } catch {
    useAlert(t('AUTONOMIA_GUIDE.HISTORY.DELETE_FAILED'));
  } finally {
    apagando.value = false;
  }
};

onMounted(carregar);
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <p
      v-if="carregando"
      class="flex items-center gap-2 mb-0 text-n-slate-11"
      role="status"
    >
      <span class="i-svg-spinner size-4 shrink-0" aria-hidden="true" />
      {{ $t('AUTONOMIA_GUIDE.HISTORY.LOADING') }}
    </p>
    <div v-else-if="falhou" class="flex flex-col items-start gap-2">
      <p class="mb-0 text-n-ruby-11">
        {{ $t('AUTONOMIA_GUIDE.HISTORY.LOAD_FAILED') }}
      </p>
      <Button
        :label="$t('AUTONOMIA_GUIDE.HISTORY.RETRY')"
        icon="i-lucide-rotate-ccw"
        slate
        faded
        class="min-h-11"
        @click="carregar"
      />
    </div>
    <div v-else-if="vazia" class="flex flex-col gap-1">
      <p class="mb-0 text-n-slate-12 font-medium">
        {{ $t('AUTONOMIA_GUIDE.HISTORY.EMPTY_TITLE') }}
      </p>
      <p class="mb-0 text-n-slate-11">
        {{ $t('AUTONOMIA_GUIDE.HISTORY.EMPTY', { dias: retencao }) }}
      </p>
    </div>
    <template v-else>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ $t('AUTONOMIA_GUIDE.HISTORY.KEPT_FOR', { dias: retencao }) }}
      </p>
      <ul class="flex flex-col gap-1 m-0 p-0 list-none">
        <li
          v-for="conversa in conversas"
          :key="conversa.id"
          class="flex items-stretch gap-1 rounded-lg"
          :class="
            conversa.id === props.conversaAtual
              ? 'bg-n-alpha-2'
              : 'hover:bg-n-alpha-1'
          "
        >
          <button
            type="button"
            data-conversa
            class="flex flex-col flex-1 min-w-0 min-h-11 px-3 py-2 text-start rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-current="conversa.id === props.conversaAtual ? 'true' : null"
            @click="emit('abrir', conversa.id)"
          >
            <span class="text-sm text-n-slate-12 truncate">
              {{ conversa.titulo || $t('AUTONOMIA_GUIDE.HISTORY.NO_TITLE') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ haQuanto(conversa.atualizada_em) }}
            </span>
          </button>
          <Button
            v-tooltip="$t('AUTONOMIA_GUIDE.HISTORY.DELETE')"
            :aria-label="
              $t('AUTONOMIA_GUIDE.HISTORY.DELETE_NAMED', {
                titulo: conversa.titulo,
              })
            "
            icon="i-lucide-trash-2"
            ghost
            slate
            lg
            class="shrink-0 self-center"
            @click="pedirParaApagar(conversa)"
          />
        </li>
      </ul>
      <Button
        v-if="temMais"
        :label="$t('AUTONOMIA_GUIDE.HISTORY.MORE')"
        :is-loading="carregandoMais"
        slate
        faded
        class="min-h-11 self-start"
        @click="verMais"
      />
    </template>

    <Dialog
      ref="dialogo"
      type="alert"
      width="sm"
      :title="$t('AUTONOMIA_GUIDE.HISTORY.CONFIRM_TITLE')"
      :description="$t('AUTONOMIA_GUIDE.HISTORY.CONFIRM_TEXT')"
      :confirm-button-label="$t('AUTONOMIA_GUIDE.HISTORY.CONFIRM')"
      :cancel-button-label="$t('AUTONOMIA_GUIDE.HISTORY.KEEP')"
      :is-loading="apagando"
      @confirm="apagar"
      @close="paraApagar = null"
    />
  </div>
</template>
