<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTextareaAutosize } from '@vueuse/core';
import {
  MAX_ANEXOS_POR_CONVERSA,
  TIPOS_DE_ANEXO,
} from 'dashboard/store/modules/autonomiaGuide';

// #982 — a porta de entrada da tela vazia: uma pergunta, um campo e um botão.
// O texto (e os prints ou arquivos que explicam o pedido) vai para a tela de
// nova automação, onde o Guia monta. As ideias preenchem o campo para a pessoa
// ver como se pede.
defineProps({
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['pedir', 'falar']);

const { t } = useI18n();
// O pedido costuma ser longo ("quando chegar o e-mail X, criar contato, card…"): o campo cresce
// com o texto até um teto e depois rola, para a pessoa ler o que escreveu.
const MAX_CARACTERES = 5000;
const { textarea, input: pedido } = useTextareaAutosize();
const IDEIAS = ['RECLAMACAO', 'FORA_DO_HORARIO', 'ORCAMENTO'];
const ideias = computed(() =>
  IDEIAS.map(chave => t(`AUTOMACOES.HEROI.IDEIAS.${chave}`))
);

// Prints e arquivos que a pessoa juntou. Sobem só na tela do Guia; aqui ficam
// com a miniatura para ela ver o que vai junto.
const anexos = ref([]);
const seletor = ref(null);
const arrastando = ref(false);
let proximoId = 0;

const juntar = arquivos => {
  const livres = MAX_ANEXOS_POR_CONVERSA - anexos.value.length;
  const novos = Array.from(arquivos || [])
    .slice(0, Math.max(livres, 0))
    .map(file => {
      proximoId += 1;
      const ehFoto = (file.type || '').startsWith('image/');
      return {
        id: proximoId,
        file,
        nome: file.name,
        previa: ehFoto ? URL.createObjectURL(file) : null,
      };
    });
  anexos.value = [...anexos.value, ...novos];
};

const soltar = anexo => {
  if (anexo.previa) URL.revokeObjectURL(anexo.previa);
};

const remover = id => {
  const anexo = anexos.value.find(item => item.id === id);
  if (anexo) soltar(anexo);
  anexos.value = anexos.value.filter(item => item.id !== id);
};

onBeforeUnmount(() => anexos.value.forEach(soltar));

const cabeMais = computed(() => anexos.value.length < MAX_ANEXOS_POR_CONVERSA);
const temAlgo = computed(
  () => Boolean((pedido.value || '').trim()) || anexos.value.length > 0
);

const aoEscolher = evento => {
  juntar(evento.target.files);
  evento.target.value = '';
};

// Colar um print (Ctrl/Cmd+V) junta a imagem; texto colado segue normal.
const aoColar = evento => {
  const arquivos = evento.clipboardData?.files;
  if (!arquivos?.length) return;
  evento.preventDefault();
  juntar(arquivos);
};

const aoSoltar = evento => {
  arrastando.value = false;
  juntar(evento.dataTransfer?.files);
};

const enviar = () => {
  if (!temAlgo.value) return;
  emit('pedir', {
    texto: (pedido.value || '').trim(),
    anexos: anexos.value.map(item => item.file),
  });
};

// Enter manda, como no chat; Shift+Enter quebra a linha.
const aoTeclar = evento => {
  if (evento.key !== 'Enter' || evento.shiftKey || evento.isComposing) return;
  evento.preventDefault();
  enviar();
};
</script>

<template>
  <section
    data-heroi
    class="relative overflow-hidden rounded-3xl bg-[#0D2344] px-6 py-10 text-white md:px-12 md:py-12"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col gap-5 max-w-4xl">
      <span
        class="inline-flex items-center gap-2 text-xs font-semibold tracking-wider uppercase text-n-blue-6"
      >
        <span class="i-lucide-sparkles size-4" aria-hidden="true" />
        {{ $t('AUTOMACOES.LISTA.TITULO') }}
      </span>
      <h1
        class="text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
      >
        {{ $t('AUTOMACOES.HEROI.TITULO') }}
      </h1>
      <p class="mb-0 text-base leading-relaxed md:text-lg text-white/75">
        {{ $t('AUTOMACOES.HEROI.TEXTO') }}
      </p>
      <form
        class="flex flex-col gap-1 p-2 bg-white shadow-2xl rounded-2xl transition"
        :class="arrastando ? 'ring-4 ring-n-blue-6' : ''"
        @submit.prevent="enviar"
        @dragover.prevent="arrastando = !desabilitado"
        @dragleave.prevent="arrastando = false"
        @drop.prevent="desabilitado ? null : aoSoltar($event)"
      >
        <label for="automacao-pedido" class="sr-only">
          {{ $t('AUTOMACOES.HEROI.TITULO') }}
        </label>
        <textarea
          id="automacao-pedido"
          ref="textarea"
          v-model="pedido"
          data-pedido
          rows="1"
          :maxlength="MAX_CARACTERES"
          :disabled="desabilitado"
          :placeholder="$t('AUTOMACOES.HEROI.EXEMPLO')"
          class="w-full px-3 pt-3 pb-1 text-base leading-relaxed bg-transparent border-0 outline-none resize-none min-h-[3rem] max-h-60 overflow-y-auto text-n-slate-12 placeholder:text-n-slate-10 disabled:cursor-not-allowed !mb-0"
          @keydown="aoTeclar"
          @paste="aoColar"
        />
        <ul
          v-if="anexos.length"
          data-anexos
          class="flex flex-wrap gap-2 px-1 py-1 m-0 list-none"
        >
          <li
            v-for="anexo in anexos"
            :key="anexo.id"
            class="flex items-center gap-2 py-1 ps-1 pe-0 rounded-xl bg-n-slate-2 ring-1 ring-inset ring-n-weak max-w-[16rem]"
          >
            <img
              v-if="anexo.previa"
              :src="anexo.previa"
              :alt="anexo.nome"
              class="object-cover rounded-lg size-10 shrink-0"
            />
            <span
              v-else
              class="grid rounded-lg place-items-center size-10 shrink-0 bg-n-slate-3 text-n-slate-11"
            >
              <span class="i-lucide-file-text size-5" aria-hidden="true" />
            </span>
            <span class="text-sm truncate text-n-slate-12">
              {{ anexo.nome }}
            </span>
            <button
              type="button"
              data-remover-anexo
              :aria-label="$t('AUTOMACOES.HEROI.REMOVER', { nome: anexo.nome })"
              class="grid rounded-lg place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="remover(anexo.id)"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
            </button>
          </li>
        </ul>
        <div class="flex items-center gap-2">
          <button
            type="button"
            data-anexar
            :disabled="desabilitado || !cabeMais"
            :title="$t('AUTOMACOES.HEROI.ANEXAR')"
            class="inline-flex items-center gap-2 px-3 text-sm font-medium transition min-h-11 rounded-xl text-n-slate-11 hover:bg-n-slate-2 hover:text-[#0D2344] focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-40"
            @click="seletor?.click()"
          >
            <span class="i-lucide-paperclip size-5" aria-hidden="true" />
            <span class="hidden sm:inline">{{
              $t('AUTOMACOES.HEROI.ANEXAR')
            }}</span>
          </button>
          <input
            ref="seletor"
            type="file"
            multiple
            data-seletor
            :accept="TIPOS_DE_ANEXO"
            class="hidden"
            @change="aoEscolher"
          />
          <span class="flex-1" />
          <button
            type="button"
            data-falar
            :disabled="desabilitado"
            :aria-label="$t('AUTOMACOES.HEROI.FALAR')"
            :title="$t('AUTOMACOES.HEROI.FALAR')"
            class="grid place-items-center shrink-0 size-12 rounded-xl ring-1 ring-inset ring-n-weak bg-n-slate-2 text-[#0D2344] transition hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
            @click="emit('falar')"
          >
            <span class="i-lucide-mic size-6" aria-hidden="true" />
          </button>
          <button
            type="submit"
            data-montar
            :disabled="desabilitado || !temAlgo"
            class="inline-flex items-center justify-center gap-2 px-5 text-base font-semibold text-white whitespace-nowrap transition min-h-12 rounded-xl bg-n-brand hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          >
            {{ $t('AUTOMACOES.HEROI.MONTAR') }}
            <span
              class="i-lucide-arrow-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
        </div>
      </form>
      <p class="mb-0 -mt-2 text-sm text-white/60">
        {{ $t('AUTOMACOES.HEROI.DICA_ANEXO') }}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-sm text-white/60">
          {{ $t('AUTOMACOES.HEROI.IDEIAS_ROTULO') }}
        </span>
        <button
          v-for="ideia in ideias"
          :key="ideia"
          type="button"
          data-ideia
          :disabled="desabilitado"
          class="px-4 py-2 text-sm transition rounded-xl min-h-11 ring-1 ring-inset ring-white/20 bg-white/10 text-white/90 hover:bg-white/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:cursor-not-allowed"
          @click="pedido = ideia"
        >
          {{ ideia }}
        </button>
      </div>
    </div>
  </section>
</template>
