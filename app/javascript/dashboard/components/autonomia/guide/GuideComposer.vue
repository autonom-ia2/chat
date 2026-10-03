<script setup>
import { ref, nextTick, onMounted } from 'vue';

// Caixa de pergunta própria do Guia, em vez do CopilotInput compartilhado.
// O que muda em relação a ele:
//  - o botão enviar é 44x44 (lá são 36x40) e tem nome acessível — é só ícone,
//    e tooltip leitor de tela não lê;
//  - enquanto uma pergunta está em andamento o campo fica em somente-leitura
//    e aparece um aviso. Antes a segunda pergunta era engolida em silêncio.
const props = defineProps({
  // Verdadeiro enquanto a resposta da pergunta anterior não chegou.
  isBusy: {
    type: Boolean,
    default: false,
  },
  // Recebe o texto e devolve `true` quando a pergunta entrou na conversa —
  // só aí o campo é limpo.
  onSend: {
    type: Function,
    required: true,
  },
  // #857 — os arquivos anexados nesta conversa: { id, nome, estado }.
  arquivos: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['anexar', 'remover']);

const message = ref('');
const textareaRef = ref(null);
const fileRef = ref(null);

// O input de arquivo é escondido; o botão do clipe é o alvo de toque (44x44).
const escolherArquivo = () => fileRef.value?.click();

const arquivoEscolhido = event => {
  Array.from(event.target.files || []).forEach(file => emit('anexar', file));
  event.target.value = '';
};

const adjustHeight = () => {
  if (!textareaRef.value) return;
  textareaRef.value.style.height = 'auto';
  textareaRef.value.style.height = `${textareaRef.value.scrollHeight}px`;
};

const sendMessage = () => {
  if (props.isBusy || !message.value.trim()) return;
  if (!props.onSend(message.value)) return;
  message.value = '';
  nextTick(adjustHeight);
};

const handleInput = () => {
  nextTick(adjustHeight);
};

const handleEnterKey = event => {
  if (event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

onMounted(() => {
  nextTick(adjustHeight);
});
</script>

<template>
  <div>
    <!-- #857 — arquivos da conversa: o Guia lê todos a cada pergunta. -->
    <ul v-if="arquivos.length" class="flex flex-wrap gap-2 mb-2 p-0 list-none">
      <li
        v-for="arquivo in arquivos"
        :key="arquivo.id"
        class="flex items-center gap-1 max-w-full rounded-lg border border-n-weak bg-n-alpha-1 ltr:pl-3 rtl:pr-3 text-sm"
        :class="
          arquivo.estado === 'erro' ? 'text-n-ruby-11' : 'text-n-slate-12'
        "
      >
        <span
          class="size-4 shrink-0"
          :class="
            arquivo.estado === 'subindo'
              ? 'i-svg-spinner'
              : 'i-lucide-file-text text-n-slate-11'
          "
          aria-hidden="true"
        />
        <span class="truncate min-w-0">{{ arquivo.nome }}</span>
        <span v-if="arquivo.estado === 'erro'" class="sr-only">
          {{ $t('AUTONOMIA_GUIDE.FILE.FAILED') }}
        </span>
        <button
          type="button"
          :aria-label="
            $t('AUTONOMIA_GUIDE.FILE.REMOVE', { nome: arquivo.nome })
          "
          class="h-11 w-11 shrink-0 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-ruby-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
          @click="emit('remover', arquivo.id)"
        >
          <i class="i-lucide-x" />
        </button>
      </li>
    </ul>
    <form class="relative" @submit.prevent="sendMessage">
      <input
        ref="fileRef"
        type="file"
        multiple
        class="hidden"
        accept=".pdf,.docx,.xlsx,.csv,.txt,.md,.json"
        @change="arquivoEscolhido"
      />
      <button
        type="button"
        :disabled="isBusy"
        :aria-label="$t('AUTONOMIA_GUIDE.FILE.ATTACH')"
        class="absolute ltr:left-1 rtl:right-1 top-1/2 -translate-y-1/2 h-11 w-11 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-blue-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-60"
        @click="escolherArquivo"
      >
        <i class="i-lucide-paperclip" />
      </button>
      <textarea
        ref="textareaRef"
        v-model="message"
        :readonly="isBusy"
        :aria-busy="isBusy ? 'true' : 'false'"
        :placeholder="$t('CAPTAIN.COPILOT.SEND_MESSAGE')"
        class="w-full reset-base bg-n-alpha-3 ltr:pl-12 ltr:pr-14 rtl:pl-14 rtl:pr-12 py-3 text-sm border border-n-weak rounded-lg focus:outline-0 focus:outline-none focus:ring-2 focus:ring-n-blue-11 focus:border-n-blue-11 resize-none overflow-y-auto max-h-[200px] mb-0 text-n-slate-12 read-only:cursor-wait read-only:opacity-60"
        rows="1"
        @input="handleInput"
        @keydown.enter.exact="handleEnterKey"
      />
      <button
        :disabled="isBusy"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.SEND')"
        class="absolute ltr:right-1 rtl:left-1 top-1/2 -translate-y-1/2 h-11 w-11 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-blue-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-60"
        type="submit"
      >
        <i class="i-ph-arrow-up" />
      </button>
    </form>
    <!-- Aviso, não só o campo travado: quem digita rápido não repara na
         opacidade e ficava sem nenhum sinal de que a pergunta não saiu. -->
    <p v-if="isBusy" class="mt-1 mb-0 text-sm text-n-slate-11">
      {{ $t('AUTONOMIA_GUIDE.SENDING') }}
    </p>
  </div>
</template>
