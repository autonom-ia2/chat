<script setup>
// Uma linha de arquivo na Nova campanha: o topo do modelo (#1465) ou um cartão
// do carrossel (#1334). Diz o que vai — o arquivo aprovado com o modelo, o que
// a pessoa escolheu agora ou o que está subindo — e oferece Escolher/Trocar e
// "Usar o aprovado". Quem sobe o arquivo é o PonteFormatoDaCampanha.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolherArquivo from '../components/criar/EscolherArquivo.vue';
import { ACEITA } from '../helpers/formatoNaCampanha';

const props = defineProps({
  titulo: { type: String, required: true },
  // 'foto' | 'video' | 'documento'
  midia: { type: String, required: true },
  // { nome } do arquivo aprovado com o modelo, ou null.
  guardado: { type: Object, default: null },
  // { referencia, nome } do arquivo escolhido agora, ou null.
  escolhido: { type: Object, default: null },
  // Nome do arquivo que está subindo ('' = nenhum).
  enviando: { type: String, default: '' },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['escolhido', 'voltar']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.FORMATO.ARQUIVO';
const ICONES = {
  foto: 'i-lucide-image',
  video: 'i-lucide-video',
  documento: 'i-lucide-file-text',
};

const descricao = computed(() => {
  if (props.enviando) {
    return t(`${NS}.ENVIANDO`, { arquivo: props.enviando });
  }
  if (props.escolhido) {
    return t(`${NS}.ESCOLHIDO`, { arquivo: props.escolhido.nome });
  }
  if (props.guardado) {
    return t(`${NS}.GUARDADO.${props.midia}`, { arquivo: props.guardado.nome });
  }
  return t(`${NS}.SEM_ARQUIVO.${props.midia}`);
});
const rotulo = computed(() =>
  props.guardado || props.escolhido
    ? t(`${NS}.TROCAR.${props.midia}`)
    : t(`${NS}.ESCOLHER.${props.midia}`)
);
</script>

<template>
  <div
    class="flex flex-wrap gap-3 items-center p-3 rounded-xl border border-n-weak bg-n-solid-1"
  >
    <span
      class="flex justify-center items-center rounded-lg size-11 shrink-0 bg-n-blue-3 text-n-blue-11"
      aria-hidden="true"
    >
      <span :class="ICONES[midia]" class="size-5" />
    </span>
    <span class="flex flex-col flex-1 min-w-0 basis-48">
      <strong class="text-sm text-n-slate-12">{{ titulo }}</strong>
      <span class="text-xs break-words text-n-slate-11" aria-live="polite">
        {{ descricao }}
      </span>
      <span v-if="erro" role="alert" class="text-xs text-n-ruby-11">
        {{ erro }}
      </span>
    </span>
    <span class="flex flex-wrap gap-2 items-center w-full sm:w-auto">
      <EscolherArquivo
        :aceita="ACEITA[midia]"
        :rotulo="rotulo"
        @escolhido="arquivo => emit('escolhido', arquivo)"
      />
      <button
        v-if="guardado && escolhido"
        type="button"
        data-usar-aprovado
        class="px-2 text-sm min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded-lg"
        @click="emit('voltar')"
      >
        {{ t(`${NS}.VOLTAR.${midia}`) }}
      </button>
    </span>
  </div>
</template>
