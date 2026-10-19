<script setup>
// O e-mail HTML do remetente como ele desenhou (#1884): numa moldura isolada (iframe
// sandbox, sem script), com o documento inteiro. A moldura cresce com o conteúdo (sem
// rolagem própria) e repassa a altura a quem a usa (recolher e-mail longo). Clicar na
// foto do corpo abre a imagem, como antes (#1869).
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import { semRastreio } from './dadosDoEmail';
import { telaDoPainel } from './cssDaMoldura';
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
// Teto da altura, e um disjuntor de última proteção (o vh e a @media de altura já viram
// medida fixa em cssDaMoldura.js): mais de 20 mudanças em 1 s sem imagem carregando nem
// clique da pessoa → a medida pausa. Imagem que carrega, largura nova ou clique religam.
const ALTURA_MAXIMA = 60000;
const MUDANCAS_POR_SEGUNDO = 20;
const UM_SEGUNDO = 1000;

const moldura = useTemplateRef('moldura');
const documento = computed(() =>
  documentoIsolado(props.html, { semRastreio, tela: telaDoPainel() })
);
const altura = ref(0);

let documentoLigado = null;
let observador = null;
let espera = 0;
let recentes = [];
let pausada = false;
let larguraMedida = 0;

const definirAltura = nova => {
  altura.value = nova;
  emit('altura', nova);
};

const religar = () => {
  recentes = [];
  pausada = false;
};

// Largura nova (janela ou painel) explica a mudança: o disjuntor religa.
const religarSeMudouALargura = () => {
  const largura = moldura.value.clientWidth;
  if (largura === larguraMedida) return;
  larguraMedida = largura;
  religar();
};

const mudouDemais = () => {
  const agora = performance.now();
  recentes = [...recentes.filter(t => agora - t < UM_SEGUNDO), agora];
  return recentes.length > MUDANCAS_POR_SEGUNDO;
};

const alturaDoConteudo = () => {
  const raiz = documentoLigado.documentElement;
  // Barra de rolagem de lado (e-mail mais largo que a tela), quando ocupa lugar.
  const barra = Math.max(0, moldura.value.clientHeight - raiz.clientHeight);
  // O que passa do fim do <body> (margem negativa, por exemplo) também conta.
  const corpo = documentoLigado.body;
  const fimDoCorpo = corpo
    ? corpo.getBoundingClientRect().top + corpo.scrollHeight
    : 0;
  const conteudo = Math.max(raiz.getBoundingClientRect().height, fimDoCorpo);
  return Math.min(ALTURA_MAXIMA, Math.ceil(conteudo) + barra);
};

// `explicada`: a mudança veio de imagem carregando (não conta para o disjuntor).
const medir = ({ explicada = false } = {}) => {
  if (!documentoLigado?.documentElement || !moldura.value) return;
  // Escondida (aba, recolhida): sem largura, a medida seria 0 e não vale.
  if (!moldura.value.clientWidth) return;
  religarSeMudouALargura();
  if (pausada) return;
  const nova = alturaDoConteudo();
  if (nova === altura.value) return;
  if (!explicada && mudouDemais()) pausada = true;
  definirAltura(nova);
};

const medirSozinho = () => medir();
// Clique da pessoa (abrir um <details>, por exemplo): religa e mede na hora.
const aoClicar = () => {
  religar();
  medir();
};
const aoCarregar = () => {
  religar();
  medir({ explicada: true });
};

const desligar = () => {
  documentoLigado?.removeEventListener('click', abrirImagemDoCorpo);
  documentoLigado?.removeEventListener('load', aoCarregar, true);
  documentoLigado?.removeEventListener('click', aoClicar);
  observador?.disconnect();
  observador = null;
  documentoLigado = null;
};

const ligar = doc => {
  desligar();
  documentoLigado = doc;
  religar();
  larguraMedida = 0;
  doc.addEventListener('click', abrirImagemDoCorpo);
  // Imagem que termina de carregar muda a altura (e explica a mudança). Clique da pessoa
  // (abrir um <details>, por exemplo) também.
  doc.addEventListener('load', aoCarregar, true);
  doc.addEventListener('click', aoClicar);
  if (typeof ResizeObserver !== 'undefined') {
    observador = new ResizeObserver(medirSozinho);
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
    class="block w-full border-0 bg-white dark:rounded-lg"
    :style="{ height: `${altura}px` }"
    data-corpo-isolado-do-email
    @load="carregou"
  />
</template>
