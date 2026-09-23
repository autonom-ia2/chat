<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useLevarAteLa } from 'dashboard/composables/useLevarAteLa';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConteudoDoArtigo from '../components/ConteudoDoArtigo.vue';
import TamanhoDaLetra from '../components/TamanhoDaLetra.vue';
import { useTamanhoDaLetra } from '../composables/useTamanhoDaLetra';

const { t, locale } = useI18n();
const route = useRoute();
const store = useStore();
const { updateUISettings } = useUISettings();
const contaAtual = useMapGetter('accounts/getAccount');
const { destino, levar } = useLevarAteLa();
const { classe: classeDaLetra } = useTamanhoDaLetra();

const artigo = ref(null);
const carregando = ref(true);
const naoEncontrado = ref(false);
const erro = ref(false);
const topo = ref(null);

const accountId = computed(() => store.getters.getCurrentAccountId);
const guiaDisponivel = computed(
  () => contaAtual.value(accountId.value)?.autonomia_guide_available === true
);

// Sem botão quando a tela não existe para a conta (recurso desligado, rota fora da lista do Guia).
const levarAteLa = computed(() => {
  const alvo = artigo.value?.me_leve_ate_la;
  return alvo && destino(alvo.rota) ? alvo : null;
});

const atualizadoEm = computed(() =>
  artigo.value?.atualizado_em
    ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
        day: 'numeric',
        month: 'long',
        year: 'numeric',
      }).format(new Date(artigo.value.atualizado_em))
    : ''
);

const carregar = async ref_ => {
  carregando.value = true;
  naoEncontrado.value = false;
  erro.value = false;
  try {
    const { data } = await CentralDeAjudaAPI.artigo(ref_);
    artigo.value = data;
  } catch (e) {
    artigo.value = null;
    if (e?.response?.status === 404) naoEncontrado.value = true;
    else erro.value = true;
  } finally {
    carregando.value = false;
    await nextTick();
    topo.value?.scrollIntoView?.({ block: 'start' });
  }
};

watch(() => route.params.ref, carregar, { immediate: true });

const irAteLa = () =>
  levar({
    rota: levarAteLa.value.rota,
    destaque: levarAteLa.value.destaque,
  });

const perguntarAoGuia = () =>
  updateUISettings({
    is_autonomia_guide_panel_open: true,
    is_autonomia_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });

const rotaDoArtigo = vizinho => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: vizinho.ref },
});
</script>

<template>
  <section class="h-full w-full overflow-y-auto">
    <div ref="topo" class="max-w-3xl mx-auto px-4 py-8 flex flex-col gap-6">
      <nav class="flex flex-wrap items-center gap-2 text-base">
        <router-link
          :to="{ name: 'central_de_ajuda' }"
          class="inline-flex items-center gap-2 min-h-11 px-3 -ml-3 rounded-xl text-n-blue-11 font-medium hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          <span class="i-lucide-arrow-left size-5" aria-hidden="true" />
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.VOLTAR') }}
        </router-link>
        <template v-if="artigo?.capitulo">
          <span
            class="i-lucide-chevron-right size-4 text-n-slate-9 rtl:rotate-180"
            aria-hidden="true"
          />
          <span class="text-n-slate-11">{{ artigo.capitulo }}</span>
        </template>
      </nav>

      <div v-if="carregando" class="flex justify-center py-16">
        <Spinner />
      </div>

      <p
        v-else-if="naoEncontrado"
        class="mb-0 py-12 text-center text-lg text-n-slate-11"
      >
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.NAO_ENCONTRADO') }}
      </p>

      <div
        v-else-if="erro"
        class="flex flex-col items-center gap-4 py-12 text-center"
      >
        <p class="mb-0 text-lg text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TEXTO') }}
        </p>
        <Button
          size="lg"
          color="slate"
          variant="outline"
          class="min-h-11"
          :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TENTAR')"
          @click="carregar(route.params.ref)"
        />
      </div>

      <template v-else-if="artigo">
        <header class="flex flex-col gap-5">
          <h1 class="mb-0 text-3xl font-semibold leading-tight text-n-slate-12">
            {{ artigo.titulo }}
          </h1>
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div v-if="levarAteLa" class="flex flex-col gap-1">
              <Button
                size="lg"
                color="blue"
                icon="i-lucide-navigation"
                class="min-h-12 px-6 text-base"
                :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.ME_LEVE')"
                @click="irAteLa"
              />
              <span class="text-sm text-n-slate-11">
                {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.ME_LEVE_AJUDA') }}
              </span>
            </div>
            <TamanhoDaLetra class="ltr:ml-auto rtl:mr-auto" />
          </div>
        </header>

        <ConteudoDoArtigo
          :conteudo="artigo.conteudo"
          :classe-da-letra="classeDaLetra"
        />

        <p v-if="atualizadoEm" class="mb-0 text-sm text-n-slate-10">
          {{
            t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.ATUALIZADO', {
              data: atualizadoEm,
            })
          }}
        </p>

        <nav
          v-if="artigo.anterior || artigo.proximo"
          class="grid gap-3 sm:grid-cols-2"
        >
          <router-link
            v-if="artigo.anterior"
            :to="rotaDoArtigo(artigo.anterior)"
            class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-5 py-4 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            <span class="text-sm text-n-slate-11">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.ANTERIOR') }}
            </span>
            <span class="text-base font-medium text-n-slate-12">
              {{ artigo.anterior.titulo }}
            </span>
          </router-link>
          <router-link
            v-if="artigo.proximo"
            :to="rotaDoArtigo(artigo.proximo)"
            class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-5 py-4 text-right hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand sm:col-start-2"
          >
            <span class="text-sm text-n-slate-11">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PROXIMO') }}
            </span>
            <span class="text-base font-medium text-n-slate-12">
              {{ artigo.proximo.titulo }}
            </span>
          </router-link>
        </nav>

        <aside
          v-if="guiaDisponivel"
          class="flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-n-alpha-1 px-6 py-5"
        >
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-lg font-medium text-n-slate-12">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.AJUDA_TITULO') }}
            </p>
            <p class="mb-0 text-base text-n-slate-11">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.AJUDA_TEXTO') }}
            </p>
          </div>
          <Button
            size="lg"
            color="blue"
            variant="faded"
            icon="i-lucide-life-buoy"
            class="min-h-11"
            :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PERGUNTE')"
            @click="perguntarAoGuia"
          />
        </aside>
      </template>
    </div>
  </section>
</template>
