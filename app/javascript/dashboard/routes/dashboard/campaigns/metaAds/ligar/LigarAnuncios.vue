<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import MetaAdsFacebookLoginCard from '../components/MetaAdsFacebookLoginCard.vue';
import MetaAdsAccountStep from '../components/MetaAdsAccountStep.vue';
import MetaAdsDestinationsStep from '../components/MetaAdsDestinationsStep.vue';
import LigarPagina from './LigarPagina.vue';
import LigarInstagram from './LigarInstagram.vue';
import LigarPronto from './LigarPronto.vue';
import { PASSOS, passoDaVez, passoFeito } from './ligarPassos';
import { estadoDemo } from './ligarDemo';

// Ligar Anúncios da Meta numa conta nova (#2338): um caminho só, um passo por tela. O passo aberto fica no
// endereço (?ligar=) para recarregar, voltar do login da Meta ou chegar de outra tela (criar anúncio, comentários)
// direto no passo que falta. `?volta=criar` devolve à criação do anúncio depois de escolher a conta.
const KEY = 'CRM_KANBAN.META_ADS_HUB.LIGAR';
const route = useRoute();
const router = useRouter();

// PROTÓTIPO: o estado vem da cena da demo; no PR final, do GET da conexão + setup_status.
const estado = estadoDemo;
const FACEBOOK_LOGIN = {
  available: true,
  app_id: 'demo',
  configuration_id: 'demo',
  api_version: 'v22.0',
};
const conexao = computed(() => ({
  configured: estado.value.facebook,
  mode: 'facebook_login',
  ad_account: estado.value.adAccount,
  pixel: estado.value.adAccount ? { id: 'px_1', name: 'Site da Loja' } : null,
  facebook_login: FACEBOOK_LOGIN,
}));

const tela = computed(() => {
  const pedido = String(route.query.ligar || '').toUpperCase();
  return [...PASSOS, 'PRONTO'].includes(pedido) ? pedido : 'INICIO';
});
const numero = computed(() => PASSOS.indexOf(tela.value) + 1);

const abrir = passo => {
  router.replace({ query: { ...route.query, ligar: passo.toLowerCase() } });
};
const seguir = () => {
  if (route.query.volta === 'criar' && estado.value.adAccount) {
    router.replace({ query: { aba: 'resultado', criar: 'novo' } });
    return;
  }
  abrir(passoDaVez(estado.value));
};

const progresso = computed(() =>
  PASSOS.map(passo => ({
    passo,
    feito: passoFeito(passo, estado.value),
    agora: passo === tela.value,
  }))
);

const escolherPagina = page => {
  estado.value = { ...estado.value, page };
  seguir();
};
const instagramLigado = () => {
  estado.value = { ...estado.value, instagramInbox: true };
  seguir();
};
const numerosLiberados = () => {
  estado.value = { ...estado.value, pageInsights: true };
};
const destinosGravados = data => {
  estado.value = { ...estado.value, destinations: data.destinations };
  seguir();
};
</script>

<template>
  <div
    data-ligar-anuncios
    :data-ligar-tela="tela"
    class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_20rem]"
  >
    <section
      class="flex flex-col gap-5 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-8"
    >
      <template v-if="tela === 'INICIO'">
        <span
          class="flex items-center justify-center size-12 rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-megaphone size-6" />
        </span>
        <div class="flex flex-col gap-2">
          <h2 class="m-0 text-xl font-semibold text-n-slate-12">
            {{ $t(`${KEY}.INICIO.TITLE`) }}
          </h2>
          <p class="m-0 text-sm leading-6 text-n-slate-11">
            {{ $t(`${KEY}.INICIO.TEXT`) }}
          </p>
        </div>
        <ol class="flex flex-col gap-3 p-0 m-0 list-none">
          <li
            v-for="(passo, index) in PASSOS"
            :key="passo"
            class="flex items-start gap-3"
          >
            <span
              class="flex items-center justify-center flex-none text-xs font-semibold rounded-full size-7 bg-n-alpha-2 text-n-slate-11"
              aria-hidden="true"
            >
              {{ index + 1 }}
            </span>
            <span class="flex flex-col">
              <span class="text-sm font-medium text-n-slate-12">
                {{ $t(`${KEY}.PASSOS.${passo}`) }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ $t(`${KEY}.PASSOS.${passo}_HINT`) }}
              </span>
            </span>
          </li>
        </ol>
        <Button
          data-ligar-comecar
          class="self-start !min-h-11"
          :label="$t(`${KEY}.INICIO.START`)"
          @click="seguir"
        />
      </template>

      <template v-else-if="tela === 'PRONTO'">
        <LigarPronto
          :estado="estado"
          @abrir="abrir"
          @numeros="numerosLiberados"
          @vendas="
            router.replace({ query: { aba: 'conexao', passo: 'vendas' } })
          "
          @painel="router.replace({ query: { aba: 'resultado' } })"
        />
      </template>

      <template v-else>
        <span class="text-xs font-medium text-n-slate-10">
          {{ $t(`${KEY}.PROGRESS`, { n: numero, total: PASSOS.length }) }}
        </span>
        <MetaAdsFacebookLoginCard
          v-if="tela === 'FACEBOOK'"
          :config="conexao.facebook_login"
          @connected="seguir"
        />
        <MetaAdsAccountStep
          v-else-if="tela === 'CONTA'"
          mode="facebook_login"
          partner-name="Hub2You"
          :current="conexao"
          :show-back="false"
          @saved="seguir"
        />
        <LigarPagina
          v-else-if="tela === 'PAGINA'"
          :pages="estado.pages"
          :escolhida="estado.page"
          @escolher="escolherPagina"
          @entrar-de-novo="abrir('FACEBOOK')"
        />
        <LigarInstagram
          v-else-if="tela === 'INSTAGRAM'"
          :page="estado.page"
          @ligado="instagramLigado"
        />
        <MetaAdsDestinationsStep
          v-else-if="tela === 'DESTINO'"
          :destinations="estado.destinations"
          @saved="destinosGravados"
        />
      </template>
    </section>

    <nav
      data-ligar-progresso
      :aria-label="$t(`${KEY}.PROGRESS_LABEL`)"
      class="order-first p-2 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 lg:order-none lg:sticky lg:top-5"
    >
      <ol class="flex flex-col gap-1 p-0 m-0 list-none">
        <li
          v-for="(item, index) in progresso"
          :key="item.passo"
          :aria-current="item.agora ? 'step' : undefined"
          class="flex items-center gap-3 px-3 py-3 rounded-xl"
          :class="item.agora ? 'bg-n-blue-2' : ''"
        >
          <span
            class="flex items-center justify-center flex-none text-xs font-semibold rounded-full size-7"
            :class="{
              'bg-n-teal-9 text-white': item.feito,
              'bg-n-blue-9 text-white': item.agora && !item.feito,
              'bg-n-alpha-2 text-n-slate-11': !item.feito && !item.agora,
            }"
            aria-hidden="true"
          >
            <span v-if="item.feito" class="i-lucide-check size-3.5" />
            <template v-else>{{ index + 1 }}</template>
          </span>
          <span
            class="flex-1 text-sm text-n-slate-12"
            :class="item.agora ? 'font-semibold' : 'font-medium'"
          >
            {{ $t(`${KEY}.PASSOS.${item.passo}`) }}
          </span>
          <button
            v-if="item.feito && !item.agora"
            type="button"
            class="px-3 text-xs font-semibold bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="abrir(item.passo)"
          >
            {{ $t(`${KEY}.CHANGE`) }}
          </button>
        </li>
      </ol>
    </nav>
  </div>
</template>
