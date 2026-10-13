<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { CAMPOS } from '../constants';
import { ajustarEspacosDosCampos, juntarTextos } from '../helpers/conteudo';
import { rotuloDoCampo as rotuloDoCampoDe } from '../helpers/campos';

defineProps({
  rotulo: { type: String, required: true },
  destacarFim: { type: Boolean, default: false },
  // Campos oferecidos para inserir; a conversa aberta (#1335) usa chaves do catálogo.
  campos: { type: Array, default: () => CAMPOS },
});

// Caixa de texto da mensagem. Os campos ("Nome do cliente") entram como
// etiqueta que não se edita letra a letra: a pessoa nunca vê {{1}}. O valor é a
// lista de pedaços (ver helpers/conteudo.js).
const pedacos = defineModel({ type: Array, required: true });

const { t } = useI18n();
const caixa = ref(null);
const intervalo = ref(null);
let ultimoEmitido = '';

const CLASSE_DA_ETIQUETA =
  'inline-flex items-center px-1.5 mx-px text-sm font-medium align-baseline rounded-md select-none bg-n-blue-3 text-n-blue-11';

const rotuloDoCampo = campo => rotuloDoCampoDe(t, campo);

const criarEtiqueta = campo => {
  const etiqueta = document.createElement('span');
  etiqueta.contentEditable = 'false';
  etiqueta.dataset.campo = campo;
  etiqueta.className = CLASSE_DA_ETIQUETA;
  etiqueta.textContent = rotuloDoCampo(campo);
  return etiqueta;
};

const desenhar = () => {
  const elemento = caixa.value;
  if (!elemento) return;
  elemento.replaceChildren();
  pedacos.value.forEach(pedaco => {
    if (pedaco.t === 'campo') {
      elemento.appendChild(criarEtiqueta(pedaco.v));
      return;
    }
    pedaco.v.split('\n').forEach((linha, indice) => {
      if (indice > 0) elemento.appendChild(document.createElement('br'));
      if (linha) elemento.appendChild(document.createTextNode(linha));
    });
  });
};

// DOM → pedaços. <br> e blocos que o navegador cria viram quebra de linha.
const lerNo = no => {
  if (no.nodeType === Node.TEXT_NODE)
    return [{ t: 'texto', v: no.textContent }];
  if (no.dataset?.campo) return [{ t: 'campo', v: no.dataset.campo }];
  if (no.nodeName === 'BR') return [{ t: 'texto', v: '\n' }];
  const filhos = Array.from(no.childNodes).flatMap(lerNo);
  return no.nodeName === 'DIV' || no.nodeName === 'P'
    ? [{ t: 'texto', v: '\n' }, ...filhos]
    : filhos;
};

const aoDigitar = () => {
  const lidos = ajustarEspacosDosCampos(
    juntarTextos(Array.from(caixa.value.childNodes).flatMap(lerNo))
  );
  ultimoEmitido = JSON.stringify(lidos);
  pedacos.value = lidos;
};

watch(pedacos, valor => {
  if (JSON.stringify(valor) !== ultimoEmitido) {
    ultimoEmitido = JSON.stringify(valor);
    desenhar();
  }
});

const guardarCursor = () => {
  const selecao = window.getSelection();
  if (!selecao?.rangeCount || !caixa.value) return;
  const atual = selecao.getRangeAt(0);
  if (caixa.value.contains(atual.commonAncestorContainer)) {
    intervalo.value = atual.cloneRange();
  }
};

const inserirCampo = campo => {
  const elemento = caixa.value;
  const etiqueta = criarEtiqueta(campo);
  const espaco = document.createTextNode(' ');
  const alvo = intervalo.value;
  if (alvo && elemento.contains(alvo.commonAncestorContainer)) {
    alvo.deleteContents();
    alvo.insertNode(espaco);
    alvo.insertNode(etiqueta);
  } else {
    elemento.append(etiqueta, espaco);
  }
  const depois = document.createRange();
  depois.setStartAfter(espaco);
  depois.collapse(true);
  const selecao = window.getSelection();
  selecao.removeAllRanges();
  selecao.addRange(depois);
  intervalo.value = depois.cloneRange();
  elemento.focus();
  aoDigitar();
};

const aoTeclar = evento => {
  if (evento.key !== 'Enter') return;
  evento.preventDefault();
  document.execCommand('insertLineBreak');
};

const aoColar = evento => {
  evento.preventDefault();
  const textoColado = evento.clipboardData?.getData('text/plain') || '';
  document.execCommand('insertText', false, textoColado);
};

onMounted(() => {
  ultimoEmitido = JSON.stringify(pedacos.value);
  desenhar();
  document.addEventListener('selectionchange', guardarCursor);
});

onBeforeUnmount(() => {
  document.removeEventListener('selectionchange', guardarCursor);
});

defineExpose({ inserirCampo });
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      ref="caixa"
      data-editor-texto
      contenteditable="true"
      role="textbox"
      aria-multiline="true"
      :aria-label="rotulo"
      class="min-h-[9rem] px-4 py-3 text-base leading-relaxed whitespace-pre-wrap break-words rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-2 focus:outline-n-brand"
      :class="destacarFim ? 'outline-2 !outline-n-ruby-8' : ''"
      @input="aoDigitar"
      @keydown="aoTeclar"
      @paste="aoColar"
    />
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.EDITOR.INSERIR_CAMPO') }}
      </span>
      <button
        v-for="campo in campos"
        :key="campo"
        type="button"
        :data-inserir="campo"
        class="inline-flex items-center gap-1 px-2.5 text-sm font-medium rounded-lg min-h-11 bg-n-blue-2 text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @mousedown.prevent
        @click="inserirCampo(campo)"
      >
        <span class="i-lucide-plus size-3.5" aria-hidden="true" />
        {{ rotuloDoCampo(campo) }}
      </button>
    </div>
  </div>
</template>
