<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import InicioHeroi from './components/InicioHeroi.vue';
import InicioCartao from './components/InicioCartao.vue';
import { useCartoes } from './useCartoes';
import { useSoComMenuNovo } from './useSoComMenuNovo';

// Página inicial de Configurações (#1617): cada assunto num cartão, cada coisa num lugar só. Abre pelo item
// Configurações do menu novo (e pelo endereço antigo de Configurações, com a flag ligada).
const { t } = useI18n();
useSoComMenuNovo();
const {
  termo,
  buscando,
  grupos,
  encontrados,
  primeiraPendencia,
  trilhaCarregada,
  carregado,
} = useCartoes();

const anuncio = computed(() =>
  buscando.value
    ? t(
        'SETTINGS_INICIO.BUSCA.RESULTADOS',
        { count: encontrados.value },
        encontrados.value
      )
    : ''
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-8 px-5 py-8 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <InicioHeroi
          v-model:termo="termo"
          :comece="primeiraPendencia"
          :tudo-pronto="trilhaCarregada && !primeiraPendencia"
        />

        <p class="sr-only" aria-live="polite">{{ anuncio }}</p>

        <div
          v-if="!carregado"
          aria-busy="true"
          class="grid gap-5 grid-cols-[repeat(auto-fill,minmax(min(100%,18rem),1fr))]"
        >
          <span class="sr-only">{{ t('SETTINGS_INICIO.CARREGANDO') }}</span>
          <div
            v-for="indice in 6"
            :key="indice"
            class="h-56 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <section
          v-for="grupo in grupos"
          :key="grupo.id"
          :aria-labelledby="`inicio-grupo-${grupo.id}`"
          :data-grupo="grupo.id"
          class="flex flex-col gap-4"
        >
          <h2
            :id="`inicio-grupo-${grupo.id}`"
            class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12"
          >
            {{ grupo.titulo }}
          </h2>
          <ul
            class="grid p-0 m-0 list-none gap-5 grid-cols-[repeat(auto-fill,minmax(min(100%,18rem),1fr))]"
          >
            <InicioCartao
              v-for="cartao in grupo.cartoes"
              :key="cartao.id"
              :cartao="cartao"
            />
          </ul>
        </section>

        <div
          v-if="carregado && buscando && !encontrados"
          data-nada
          class="flex flex-col items-center gap-3 px-6 py-12 text-center rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
        >
          <span
            class="grid place-items-center size-14 rounded-2xl bg-n-slate-3 text-n-slate-11"
            aria-hidden="true"
          >
            <span class="i-lucide-search-x size-7" />
          </span>
          <p class="mb-0 text-lg text-n-slate-12">
            {{ t('SETTINGS_INICIO.BUSCA.NADA') }}
          </p>
        </div>
      </div>
    </main>
  </section>
</template>
