<script setup>
// Onda ao vivo do ditado (#1786), como a do gravador do WhatsApp: barrinhas que entram
// pela direita com o volume da voz. Pausado, a onda congela. A cor é a do texto
// (currentColor), então segue o tema.
import { onBeforeUnmount, useTemplateRef, watch } from 'vue';

const props = defineProps({
  fluxo: { type: Object, default: null },
  pausado: { type: Boolean, default: false },
});

const BARRA = 3;
const ESPACO = 2;
const INTERVALO = 70;
const MINIMO = 0.08;
// O volume da fala raramente passa de 0,3 (RMS): o ganho deixa a onda visível.
const GANHO = 3.2;

const tela = useTemplateRef('tela');
let contexto = null;
let analisador = null;
let amostras = null;
let niveis = [];
let relogio = null;

const desenhar = () => {
  const canvas = tela.value;
  if (!canvas) return;
  const escala = window.devicePixelRatio || 1;
  const { width, height } = canvas.getBoundingClientRect();
  if (canvas.width !== Math.round(width * escala)) {
    canvas.width = Math.round(width * escala);
    canvas.height = Math.round(height * escala);
  }
  const g = canvas.getContext('2d');
  g.setTransform(escala, 0, 0, escala, 0, 0);
  g.clearRect(0, 0, width, height);
  g.fillStyle = getComputedStyle(canvas).color;
  const cabem = Math.floor(width / (BARRA + ESPACO));
  const visiveis = niveis.slice(-cabem);
  visiveis.forEach((nivel, i) => {
    const altura = Math.max(2, nivel * height);
    const x = width - (visiveis.length - i) * (BARRA + ESPACO);
    g.beginPath();
    g.roundRect(x, (height - altura) / 2, BARRA, altura, BARRA / 2);
    g.fill();
  });
};

const medir = () => {
  if (!analisador || props.pausado) return;
  analisador.getFloatTimeDomainData(amostras);
  const soma = amostras.reduce((total, v) => total + v * v, 0);
  const rms = Math.sqrt(soma / amostras.length);
  niveis = [...niveis.slice(-200), Math.min(1, Math.max(MINIMO, rms * GANHO))];
  desenhar();
};

const parar = () => {
  clearInterval(relogio);
  contexto?.close().catch(() => {});
  contexto = null;
  analisador = null;
};

watch(
  () => props.fluxo,
  fluxo => {
    parar();
    niveis = [];
    if (!fluxo) return;
    contexto = new AudioContext();
    analisador = contexto.createAnalyser();
    analisador.fftSize = 512;
    amostras = new Float32Array(analisador.fftSize);
    contexto.createMediaStreamSource(fluxo).connect(analisador);
    relogio = setInterval(medir, INTERVALO);
  },
  { immediate: true }
);

onBeforeUnmount(parar);
</script>

<template>
  <canvas ref="tela" class="block w-full h-full" aria-hidden="true" />
</template>
