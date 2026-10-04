<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useLevarAteLa } from 'dashboard/composables/useLevarAteLa';
import Button from 'dashboard/components-next/button/Button.vue';
import { iconeDoCapitulo } from '../helpers/icones';
import {
  nomeCurtoDe,
  minutosDeVideo,
  temVideo,
  proximoDoAssunto,
} from '../helpers/assunto';

// Topo da página do assunto: nome, fatos e as duas ações (seguir lendo; abrir a tela do assunto).
const props = defineProps({
  capitulo: { type: Object, required: true },
  foiVisto: { type: Function, required: true },
});

const { t } = useI18n();
const router = useRouter();
const { destino, levar } = useLevarAteLa();

const artigos = computed(() => props.capitulo.artigos);

// Assunto de capítulo novo, ainda sem nome curto, usa o título que veio da API.
const nome = computed(() => {
  const chave = nomeCurtoDe(props.capitulo.id);
  return chave
    ? t(`HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.${chave}`)
    : props.capitulo.titulo;
});

const videos = computed(() => artigos.value.filter(temVideo).length);
const minutos = computed(() => minutosDeVideo(artigos.value));
const vistos = computed(
  () => artigos.value.filter(artigo => props.foiVisto(artigo.id)).length
);

const proximo = computed(() => proximoDoAssunto(artigos.value, props.foiVisto));
const rotuloDoProximo = computed(() => {
  const { modo, artigo } = proximo.value;
  if (modo === 'CONTINUAR') {
    return t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.CONTINUAR', {
      titulo: artigo.titulo,
    });
  }
  return modo === 'REVER'
    ? t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.REVER')
    : t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.COMECAR');
});
const seguir = () =>
  router.push({
    name: 'central_de_ajuda_artigo',
    params: { ref: proximo.value.artigo.ref },
  });

// A tela do assunto é o "Me leve até lá" do primeiro artigo cuja tela existe para a conta. Sem
// nenhuma (recurso desligado), não há botão. Rota da própria Central não conta: "Abrir" traria a
// pessoa de volta para cá.
const ehDaCentral = rota => rota.startsWith('central_de_ajuda');
const telaDoAssunto = computed(
  () =>
    artigos.value.find(
      artigo => artigo.rota && !ehDaCentral(artigo.rota) && destino(artigo.rota)
    )?.rota || null
);
const abrirTela = () => levar({ rota: telaDoAssunto.value });
</script>

<template>
  <header class="flex flex-col gap-5">
    <router-link
      :to="{ name: 'central_de_ajuda' }"
      class="inline-flex min-h-11 items-center gap-2 self-start rounded-xl px-3 font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand ltr:-ml-3 rtl:-mr-3"
    >
      <span
        class="i-lucide-arrow-left size-5 rtl:rotate-180"
        aria-hidden="true"
      />
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.VOLTAR') }}
    </router-link>

    <div class="flex items-start gap-4">
      <span
        class="grid size-14 shrink-0 place-items-center rounded-2xl bg-n-brand text-white"
        aria-hidden="true"
      >
        <span class="size-7" :class="iconeDoCapitulo(capitulo.id)" />
      </span>
      <div class="flex min-w-0 flex-col gap-2">
        <h1 class="mb-0 text-3xl font-semibold leading-tight text-n-slate-12">
          {{ nome }}
        </h1>
        <ul
          class="m-0 flex list-none flex-wrap gap-x-4 gap-y-1 p-0 text-base text-n-slate-11"
        >
          <li class="inline-flex items-center gap-1.5">
            <span class="i-lucide-book-open size-4" aria-hidden="true" />
            {{
              t(
                'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGOS_NO_CAPITULO',
                artigos.length
              )
            }}
          </li>
          <li v-if="videos" class="inline-flex items-center gap-1.5">
            <span class="i-lucide-circle-play size-4" aria-hidden="true" />
            {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.VIDEOS', videos) }}
          </li>
          <li v-if="minutos" class="inline-flex items-center gap-1.5">
            <span class="i-lucide-clock size-4" aria-hidden="true" />
            {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.MINUTOS', minutos) }}
          </li>
          <li class="inline-flex items-center gap-1.5">
            <span class="i-lucide-circle-check size-4" aria-hidden="true" />
            {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VISTOS', vistos) }}
          </li>
        </ul>
      </div>
    </div>

    <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap">
      <!-- Botão próprio, não o Button: lá o rótulo trunca, e aqui o título do artigo é a
           informação. No celular ele quebra linha em vez de virar reticências. -->
      <button
        type="button"
        class="inline-flex min-h-12 max-w-full items-center gap-2 rounded-lg bg-n-brand px-5 py-2.5 text-start text-base font-medium text-white hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand max-sm:w-full"
        @click="seguir"
      >
        <span
          class="size-5 shrink-0"
          :class="
            proximo.modo === 'REVER' ? 'i-lucide-rotate-ccw' : 'i-lucide-play'
          "
          aria-hidden="true"
        />
        <span class="min-w-0 break-words">{{ rotuloDoProximo }}</span>
      </button>
      <Button
        v-if="telaDoAssunto"
        size="lg"
        color="slate"
        variant="outline"
        icon="i-lucide-navigation"
        class="min-h-11 max-w-full max-sm:w-full"
        :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.ABRIR', { nome })"
        @click="abrirTela"
      />
    </div>
  </header>
</template>
