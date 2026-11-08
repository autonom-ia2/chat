<script setup>
// O e-mail HTML do remetente como ele desenhou (#1884): numa moldura isolada (iframe
// sandbox, sem script), com o documento inteiro. A moldura cresce com o conteúdo (sem
// rolagem própria) e repassa a altura a quem a usa (recolher e-mail longo). Clicar na
// foto do corpo abre a imagem, como antes (#1869).
// #1916: a imagem web só carrega perto da tela; a âncora interna rola a conversa; o
// clique e as teclas dentro do e-mail chegam ao painel (fechar menu, atalho).
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import { semRastreio } from './dadosDoEmail';
import { telaDoPainel } from './cssDaMoldura';
import { abrirImagemDoCorpo } from './imagemDoCorpo';
import { imagemSegura } from './enderecoDoEmail';
import {
  ANCORA_INTERNA,
  IMAGEM_ADIADA,
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
// Pausada, tenta de novo depois de um tempo (poucas vezes): a altura final vale.
const RETOMAR_EM = 1000;
const RETOMADAS = 3;
// A imagem começa a carregar um pouco antes de aparecer (a pessoa rolando não vê buraco).
const PERTO_DA_TELA = '800px 0px';
// O que o painel escuta no próprio documento: clique fora fecha menu (vue3-click-away no
// click, onClickOutside do VueUse no pointerdown) e os atalhos de teclado (keydown).
// O construtor é lido na hora: ambiente sem PointerEvent (testes) cai no MouseEvent.
const EVENTOS_DO_PAINEL = {
  pointerdown: 'PointerEvent',
  click: 'MouseEvent',
  keydown: 'KeyboardEvent',
};
// O Safari (WebKit) não roda nenhum ouvinte do painel dentro da moldura sem
// allow-scripts ("Blocked script execution… allow-scripts"; o clique na foto também não
// abre lá). Nele o clique só aparece como o foco saindo do painel para a moldura. Nos
// outros, o primeiro evento repassado prova que os ouvintes funcionam, e o foco não
// dispara nada (nem com Tab até o e-mail).
const COPIAR_DO_EVENTO = [
  'key',
  'code',
  'repeat',
  'ctrlKey',
  'shiftKey',
  'altKey',
  'metaKey',
  'button',
  'buttons',
  'pointerType',
];

const moldura = useTemplateRef('moldura');
const documento = computed(() =>
  documentoIsolado(props.html, { semRastreio, tela: telaDoPainel() })
);
const altura = ref(0);

let documentoLigado = null;
let observador = null;
let vigiaDeImagens = null;
let ouvintesFuncionam = false;
let espera = 0;
let recentes = [];
let pausada = false;
let larguraMedida = 0;
let retomada = 0;
let retomadas = 0;

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
  const noUltimoSegundo = recentes.filter(t => agora - t < UM_SEGUNDO);
  // Um segundo sem mudança: o laço acabou, as retomadas recomeçam.
  if (!noUltimoSegundo.length) retomadas = 0;
  recentes = [...noUltimoSegundo, agora];
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
const pausar = () => {
  pausada = true;
  if (retomadas >= RETOMADAS) return;
  retomadas += 1;
  clearTimeout(retomada);
  // Religa e mede (aoClicar, logo abaixo de medir).
  // eslint-disable-next-line no-use-before-define
  retomada = setTimeout(() => aoClicar(), RETOMAR_EM);
};

const medir = ({ explicada = false } = {}) => {
  if (!documentoLigado?.documentElement || !moldura.value) return;
  // Escondida (aba, recolhida): sem largura, a medida seria 0 e não vale.
  if (!moldura.value.clientWidth) return;
  religarSeMudouALargura();
  if (pausada) return;
  const nova = alturaDoConteudo();
  if (nova === altura.value) return;
  if (!explicada && mudouDemais()) pausar();
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

// O endereço já foi conferido ao montar o documento; confere de novo antes do src.
const carregarImagem = imagem => {
  const endereco = imagemSegura(imagem.getAttribute(IMAGEM_ADIADA));
  imagem.removeAttribute(IMAGEM_ADIADA);
  if (endereco) imagem.setAttribute('src', endereco);
};

// O observador é do painel: a interseção é com a tela de verdade (a da conversa), que a
// moldura sozinha não conhece.
const vigiarImagens = doc => {
  const adiadas = [...doc.querySelectorAll(`img[${IMAGEM_ADIADA}]`)];
  if (!adiadas.length) return;
  if (typeof IntersectionObserver === 'undefined') {
    adiadas.forEach(carregarImagem);
    return;
  }
  vigiaDeImagens = new IntersectionObserver(
    entradas =>
      entradas.forEach(({ isIntersecting, target }) => {
        if (!isIntersecting) return;
        vigiaDeImagens.unobserve(target);
        carregarImagem(target);
      }),
    { rootMargin: PERTO_DA_TELA }
  );
  adiadas.forEach(imagem => vigiaDeImagens.observe(imagem));
};

const irParaAncora = evento => {
  const link = evento.target?.closest?.(`[${ANCORA_INTERNA}]`);
  if (!link || (evento.type === 'keydown' && evento.key !== 'Enter')) return;
  evento.preventDefault();
  documentoLigado
    ?.getElementById(link.getAttribute(ANCORA_INTERNA))
    ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
};

// Uma cópia do evento no documento do painel (não na moldura: assim nenhum @click dos
// pais dela dispara). O que a âncora já tratou não vai.
const repassarAoPainel = evento => {
  ouvintesFuncionam = true;
  if (evento.defaultPrevented) return;
  const Evento = window[EVENTOS_DO_PAINEL[evento.type]] || MouseEvent;
  const copia = Object.fromEntries(
    COPIAR_DO_EVENTO.filter(nome => nome in evento).map(nome => [
      nome,
      evento[nome],
    ])
  );
  document.dispatchEvent(
    new Evento(evento.type, { ...copia, bubbles: true, cancelable: true })
  );
};

const focoEntrouNoEmail = () => {
  if (ouvintesFuncionam || document.activeElement !== moldura.value) return;
  ['pointerdown', 'click'].forEach(tipo =>
    document.dispatchEvent(
      new (window[EVENTOS_DO_PAINEL[tipo]] || MouseEvent)(tipo, {
        bubbles: true,
        cancelable: true,
      })
    )
  );
};
window.addEventListener('blur', focoEntrouNoEmail);

const desligar = () => {
  documentoLigado?.removeEventListener('click', abrirImagemDoCorpo);
  documentoLigado?.removeEventListener('load', aoCarregar, true);
  documentoLigado?.removeEventListener('click', aoClicar);
  ['click', 'keydown'].forEach(tipo =>
    documentoLigado?.removeEventListener(tipo, irParaAncora)
  );
  Object.keys(EVENTOS_DO_PAINEL).forEach(tipo =>
    documentoLigado?.removeEventListener(tipo, repassarAoPainel)
  );
  observador?.disconnect();
  observador = null;
  vigiaDeImagens?.disconnect();
  vigiaDeImagens = null;
  clearTimeout(retomada);
  documentoLigado = null;
};

const ligar = doc => {
  desligar();
  documentoLigado = doc;
  religar();
  larguraMedida = 0;
  retomadas = 0;
  doc.addEventListener('click', abrirImagemDoCorpo);
  // Imagem que termina de carregar muda a altura (e explica a mudança). Clique da pessoa
  // (abrir um <details>, por exemplo) também.
  doc.addEventListener('load', aoCarregar, true);
  doc.addEventListener('click', aoClicar);
  // A âncora antes do repasse: o que ela tratou (preventDefault) não vai ao painel.
  ['click', 'keydown'].forEach(tipo =>
    doc.addEventListener(tipo, irParaAncora)
  );
  Object.keys(EVENTOS_DO_PAINEL).forEach(tipo =>
    doc.addEventListener(tipo, repassarAoPainel)
  );
  vigiarImagens(doc);
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
  window.removeEventListener('blur', focoEntrouNoEmail);
  desligar();
});

defineExpose({ htmlParaImprimir: () => corpoParaImprimir(documento.value) });
</script>

<template>
  <!-- No tema escuro o e-mail continua em fundo branco; a folga impede o texto de colar
  na borda do cartão. -->
  <div class="bg-white dark:rounded-lg dark:p-3">
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
  </div>
</template>
