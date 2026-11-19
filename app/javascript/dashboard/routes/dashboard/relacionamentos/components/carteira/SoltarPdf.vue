<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';

// #2897 — a área grande de soltar o PDF da apólice (molde: a de soltar a
// planilha, components/trazer/SoltarArquivo.vue). É um botão de verdade: Enter
// e Espaço abrem o seletor; arrastar por cima realça. Quem usa recebe `arquivo`
// com o File escolhido. Conferir se é mesmo um PDF é com o servidor, que olha o
// conteúdo do arquivo e não o nome dele. `apoio` é a linha embaixo do convite:
// diz o que acontece depois de escolher.
//
// #2899 (E6.4) — com `varios`, aceita vários PDFs de uma vez e entrega
// `arquivos` (a lista), e o convite fala em PDFs.
//
// #3057 — redesenho: ícone forte, o convite de arrastar (no celular, "Toque
// para escolher"), e o que parece um botão azul "Escolher os PDFs" dentro da
// área. A área toda continua sendo um botão só (não há botão dentro de botão).
// No celular o "Escolher os PDFs" sai: o "Toque para escolher os PDFs" já é o
// convite, e repetir a mesma ação duas vezes só confunde.
const props = defineProps({
  apoio: { type: String, required: true },
  varios: { type: Boolean, default: false },
});
const emit = defineEmits(['arquivo', 'arquivos']);

const SO_PDF = '.pdf,application/pdf';

const { t } = useI18n();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.PDF.${chave}`);
const id = useId();
const seletor = ref(null);
const arrastando = ref(false);

const abrirSeletor = () => seletor.value?.click();

const entregar = arquivos => {
  const lista = [...(arquivos || [])];
  if (props.varios) {
    if (lista.length) emit('arquivos', lista);
    return;
  }
  const [arquivo] = lista;
  if (arquivo) emit('arquivo', arquivo);
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
  <div class="flex flex-col">
    <button
      type="button"
      data-carteira="soltar-pdf"
      :aria-describedby="`${id}-apoio`"
      class="flex flex-col items-center justify-center gap-4 p-8 text-center group transition-colors border-2 min-h-56 rounded-3xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
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
        class="flex items-center justify-center pointer-events-none size-16 rounded-2xl bg-n-blue-9 text-white shadow-md"
        aria-hidden="true"
      >
        <span class="i-lucide-file-up size-8" />
      </span>
      <span
        class="hidden text-xl font-semibold pointer-events-none sm:inline text-n-slate-12"
      >
        {{ tp(varios ? 'ARRASTE_VARIOS' : 'ARRASTE') }}
      </span>
      <span
        class="text-xl font-semibold pointer-events-none sm:hidden text-n-slate-12"
      >
        {{ tp(varios ? 'TOQUE_VARIOS' : 'TOQUE') }}
      </span>
      <span
        class="hidden text-sm pointer-events-none sm:inline text-n-slate-10"
      >
        {{ tp('OU') }}
      </span>
      <span
        data-carteira="escolher-pdfs"
        class="items-center hidden gap-2 px-6 text-base font-medium text-white sm:inline-flex rounded-lg pointer-events-none h-11 bg-n-blue-11 group-hover:bg-n-blue-12"
      >
        <span class="i-lucide-folder-open size-5" aria-hidden="true" />
        {{ tp(varios ? 'ESCOLHER_VARIOS' : 'ESCOLHER') }}
      </span>
      <span
        :id="`${id}-apoio`"
        class="text-base pointer-events-none text-n-slate-11"
      >
        {{ apoio }}
      </span>
    </button>
    <input
      ref="seletor"
      type="file"
      class="sr-only"
      tabindex="-1"
      aria-hidden="true"
      :accept="SO_PDF"
      :multiple="varios"
      @change="aoEscolher"
    />
  </div>
</template>
