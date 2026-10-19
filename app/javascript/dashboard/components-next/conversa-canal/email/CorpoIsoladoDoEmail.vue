<script setup>
// O e-mail HTML do remetente como ele desenhou (#1884): numa moldura isolada (iframe
// sandbox, sem script), com o documento inteiro. A moldura cresce com o conteúdo (sem
// rolagem própria) e repassa a altura a quem a usa (recolher e-mail longo). Clicar na
// foto do corpo abre a imagem, como antes (#1869).
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import { semRastreio } from './dadosDoEmail';
import { abrirImagemDoCorpo } from './imagemDoCorpo';
import {
  SANDBOX_DO_EMAIL,
  corpoParaImprimir,
  documentoIsolado,
} from './documentoDoEmail';

const props = defineProps({
  html: { type: String, required: true },
  titulo: { type: String, required: true },
});
const emit = defineEmits(['altura']);

// Quantos quadros esperar o documento novo aparecer antes de contar só com o "load".
const QUADROS_DE_ESPERA = 120;

const moldura = useTemplateRef('moldura');
const documento = computed(() => documentoIsolado(props.html, { semRastreio }));
const altura = ref(0);

let documentoLigado = null;
let observador = null;
let espera = 0;

const medir = () => {
  const raiz = documentoLigado?.documentElement;
  if (!raiz || !moldura.value) return;
  // Barra de rolagem de lado (e-mail mais largo que a tela), quando ocupa lugar.
  const barra = Math.max(0, moldura.value.clientHeight - raiz.clientHeight);
  // O que passa do fim do <body> (margem negativa, por exemplo) também conta.
  const corpo = documentoLigado.body;
  const fimDoCorpo = corpo
    ? corpo.getBoundingClientRect().top + corpo.scrollHeight
    : 0;
  const conteudo = Math.max(raiz.getBoundingClientRect().height, fimDoCorpo);
  const nova = Math.ceil(conteudo) + barra;
  if (nova === altura.value) return;
  altura.value = nova;
  emit('altura', nova);
};

const desligar = () => {
  documentoLigado?.removeEventListener('click', abrirImagemDoCorpo);
  documentoLigado?.removeEventListener('load', medir, true);
  observador?.disconnect();
  observador = null;
  documentoLigado = null;
};

const ligar = doc => {
  desligar();
  documentoLigado = doc;
  doc.addEventListener('click', abrirImagemDoCorpo);
  // Imagem que termina de carregar muda a altura.
  doc.addEventListener('load', medir, true);
  if (typeof ResizeObserver !== 'undefined') {
    observador = new ResizeObserver(medir);
    observador.observe(doc.documentElement);
    if (doc.body) observador.observe(doc.body);
  }
  medir();
};

// O srcdoc carrega sem avisar quando o corpo já existe; espera o documento novo quadro a
// quadro (o "load" só vem depois de todas as imagens).
const documentoNovo = () => {
  const doc = moldura.value?.contentDocument;
  if (!doc || doc === documentoLigado || doc.URL !== 'about:srcdoc')
    return null;
  return doc.body ? doc : null;
};
const esperarDocumento = () => {
  cancelAnimationFrame(espera);
  let quadros = 0;
  const olhar = () => {
    const doc = documentoNovo();
    if (doc) {
      ligar(doc);
      return;
    }
    quadros += 1;
    if (quadros < QUADROS_DE_ESPERA) espera = requestAnimationFrame(olhar);
  };
  espera = requestAnimationFrame(olhar);
};

const carregou = () => {
  const doc = documentoNovo();
  if (doc) ligar(doc);
  medir();
};

watch(documento, esperarDocumento, { flush: 'post', immediate: true });

onBeforeUnmount(() => {
  cancelAnimationFrame(espera);
  desligar();
});

defineExpose({ htmlParaImprimir: () => corpoParaImprimir(documento.value) });
</script>

<template>
  <iframe
    ref="moldura"
    :srcdoc="documento"
    :sandbox="SANDBOX_DO_EMAIL"
    :title="titulo"
    referrerpolicy="no-referrer"
    class="block w-full border-0 bg-white"
    :style="{ height: `${altura}px` }"
    data-corpo-isolado-do-email
    @load="carregou"
  />
</template>
