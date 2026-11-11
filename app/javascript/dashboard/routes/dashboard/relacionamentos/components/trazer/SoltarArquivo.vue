<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { ACEITA_NO_SELETOR } from '../../trazer/arquivo';

// #2894 — a área grande de soltar a planilha. É um botão de verdade: Enter e
// Espaço abrem o seletor; arrastar por cima realça. Quem usa recebe `arquivo`
// com o File escolhido (conferir se é planilha é com quem usa).
const props = defineProps({
  erro: { type: String, default: '' },
  // Qual foi o problema (tipo, vazia, sem_contato): fica no `data-erro`.
  tipoDeErro: { type: String, default: '' },
  // #2897 — outro arquivo que não a planilha (o PDF do seguro): quem usa diz o
  // título, o apoio, o ícone e o que o seletor aceita. Sem isso, é a planilha.
  // Com título próprio e sem apoio, a linha de apoio não aparece.
  titulo: { type: String, default: '' },
  apoio: { type: String, default: '' },
  icone: { type: String, default: 'i-lucide-file-spreadsheet' },
  aceita: { type: String, default: ACEITA_NO_SELETOR },
  // Vários de uma vez (os PDFs das apólices): sai `arquivos`, com todos.
  varios: { type: Boolean, default: false },
  // Faltou escolher: a área fica marcada e aponta para o aviso de quem usa.
  invalido: { type: Boolean, default: false },
  descritoPor: { type: String, default: '' },
});
const emit = defineEmits(['arquivo', 'arquivos']);

const { t } = useI18n();
const id = useId();
const seletor = ref(null);
const arrastando = ref(false);

const abrirSeletor = () => seletor.value?.click();

const entregar = arquivos => {
  const escolhidos = [...(arquivos || [])];
  if (!escolhidos.length) return;
  if (props.varios) emit('arquivos', escolhidos);
  else emit('arquivo', escolhidos[0]);
};

const aoEscolher = evento => {
  entregar(evento.target.files);
  // Deixa escolher o mesmo arquivo de novo depois de um erro.
  evento.target.value = '';
};

const aoSoltar = evento => {
  arrastando.value = false;
  entregar(evento.dataTransfer?.files);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <button
      type="button"
      data-relacionamentos="soltar-arquivo"
      :aria-describedby="
        descritoPor ? `${id}-apoio ${descritoPor}` : `${id}-apoio`
      "
      :aria-invalid="invalido ? 'true' : undefined"
      class="flex flex-col items-center justify-center gap-4 p-8 text-center transition-colors border-2 min-h-64 rounded-3xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      :class="
        arrastando
          ? 'border-solid border-n-blue-9 bg-n-blue-2'
          : 'border-dashed border-n-weak bg-n-solid-1 hover:border-n-blue-8 hover:bg-n-alpha-1'
      "
      @click="abrirSeletor"
      @dragenter.prevent="arrastando = true"
      @dragover.prevent="arrastando = true"
      @dragleave="arrastando = false"
      @drop.prevent="aoSoltar"
    >
      <span
        class="flex items-center justify-center rounded-full pointer-events-none size-16 bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="size-8" :class="icone" />
      </span>
      <span class="text-xl font-semibold pointer-events-none text-n-slate-12">
        {{ titulo || t('RELACIONAMENTOS_TRAZER.ENVIAR.SOLTAR') }}
      </span>
      <span
        :id="`${id}-apoio`"
        class="text-base pointer-events-none text-n-slate-11"
        :class="{ hidden: titulo && !apoio }"
      >
        {{ apoio || (titulo ? '' : t('RELACIONAMENTOS_TRAZER.ENVIAR.APOIO')) }}
      </span>
    </button>
    <input
      ref="seletor"
      type="file"
      class="sr-only"
      tabindex="-1"
      aria-hidden="true"
      :accept="aceita"
      :multiple="varios"
      @change="aoEscolher"
    />
    <p
      v-if="erro"
      data-relacionamentos="erro-da-planilha"
      :data-erro="tipoDeErro || undefined"
      role="alert"
      class="m-0 text-base text-n-ruby-11"
    >
      {{ erro }}
    </p>
  </div>
</template>
