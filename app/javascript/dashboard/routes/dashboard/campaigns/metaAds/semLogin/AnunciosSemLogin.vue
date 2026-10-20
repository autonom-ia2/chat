<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { SEM_LOGIN } from './anunciosSemLogin';
import { examplePanel } from './anunciosExemplo';
import AnunciosVazio from './AnunciosVazio.vue';
import MetaAdsPanel from '../components/MetaAdsPanel.vue';

// Anúncios sem login (#1960, degrau 0): a página abre pronta, com o mesmo painel de quem conectou a conta de
// anúncios (MetaAdsPanel), só sem gasto — o resultado sai do que o WhatsApp oficial contou. Aparece com a flag
// anuncios_sem_login, WhatsApp oficial e nenhuma conexão de anúncios. Sem ninguém vindo de anúncio em 90 dias, a
// tela "pronto" com o exemplo; quem não é administrador vê o mesmo, só leitura.
const props = defineProps({
  // { enabled, official_inboxes: [{ id, name, phone }], recent_ad_touch }
  result: { type: Object, required: true },
  readOnly: { type: Boolean, default: false },
});

const { t } = useI18n();
const example = ref(false);

const screen = computed(() => {
  if (props.result.recent_ad_touch) return 'result';
  return example.value ? 'example' : 'ready';
});

const sample = days => examplePanel(days, t);
</script>

<template>
  <div
    data-anuncios-sem-login
    :data-screen="screen"
    class="flex flex-col gap-5"
  >
    <AnunciosVazio
      v-if="screen === 'ready'"
      :inboxes="result.official_inboxes || []"
      @example="example = true"
    />

    <template v-else-if="screen === 'example'">
      <div
        data-anuncios-exemplo
        class="flex flex-wrap items-center justify-between gap-3 p-4 border border-solid rounded-2xl border-n-amber-7 bg-n-amber-2"
      >
        <span class="flex flex-wrap items-center gap-3">
          <span
            data-anuncios-exemplo-selo
            class="px-3 py-1 text-sm font-semibold rounded-full bg-n-amber-5 text-n-amber-12"
          >
            {{ $t(`${SEM_LOGIN}.EXAMPLE.BADGE`) }}
          </span>
          <span class="text-sm text-n-amber-12">
            {{ $t(`${SEM_LOGIN}.EXAMPLE.TEXT`) }}
          </span>
        </span>
        <button
          type="button"
          data-anuncios-exemplo-voltar
          class="inline-flex items-center gap-2 px-4 text-sm border border-solid rounded-xl min-h-11 font-520 border-n-amber-7 bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="example = false"
        >
          <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
          {{ $t(`${SEM_LOGIN}.EXAMPLE.BACK`) }}
        </button>
      </div>
      <MetaAdsPanel :sample="sample" read-only />
    </template>

    <MetaAdsPanel v-else :read-only="readOnly" />
  </div>
</template>
