<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { SEM_LOGIN } from './anunciosSemLogin';
import { examplePanel } from './anunciosExemplo';
import AnunciosVazio from './AnunciosVazio.vue';
import ConectarAnuncios from './ConectarAnuncios.vue';
import MetaAdsPanel from '../components/MetaAdsPanel.vue';

// Anúncios sem login (#1960, degrau 0): a página abre pronta, com o mesmo painel de quem conectou a conta de
// anúncios (MetaAdsPanel), só sem gasto — o resultado sai do que o WhatsApp oficial contou. Aparece com a flag
// anuncios_sem_login, WhatsApp oficial e nenhuma conexão de anúncios. Sem ninguém vindo de anúncio em época nenhuma, a
// tela "pronto" com o exemplo; quem não é administrador vê o mesmo, só leitura.
// "Ver quanto gastei" no painel (#2054) abre a conexão guiada no lugar dele; conectado, a página relê a conexão.
const props = defineProps({
  // { enabled, official_inboxes: [{ id, name, phone }], ad_touch, connection_state, connection_mode }
  result: { type: Object, required: true },
  // payload de GET meta_ads_connection, para o compartilhamento (partner, client_portfolio_id)
  connection: { type: Object, default: () => ({}) },
  readOnly: { type: Boolean, default: false },
});
const emit = defineEmits(['connected']);
const connecting = ref(false);
const root = ref(null);

// Voltar da conexão devolve o foco ao botão que a abriu (o da tela "pronto" ou o "Ver quanto gastei").
const closeConnect = async () => {
  connecting.value = false;
  await nextTick();
  root.value
    ?.querySelector(
      '[data-anuncios-vazio-conectar-botao], [data-panel-connect]'
    )
    ?.focus();
};

const { t } = useI18n();
const example = ref(false);

const screen = computed(() => {
  if (connecting.value) return 'connect';
  if (props.result.ad_touch) return 'result';
  return example.value ? 'example' : 'ready';
});

const sample = days => examplePanel(days, t);

// Conexão no meio do caminho ('choosing') ou caída ('broken'): um aviso no topo leva de volta à conexão guiada.
const pending = computed(() =>
  props.readOnly ? null : props.result.connection_state || null
);
const resume = computed(() =>
  pending.value
    ? { state: pending.value, mode: props.result.connection_mode }
    : null
);
</script>

<template>
  <div
    ref="root"
    data-anuncios-sem-login
    :data-screen="screen"
    class="flex flex-col gap-5"
  >
    <div
      v-if="pending && screen !== 'connect'"
      :data-anuncios-conexao="pending"
      class="flex flex-wrap items-center justify-between gap-3 rounded-2xl p-4 ring-1 ring-inset"
      :class="
        pending === 'broken'
          ? 'bg-n-amber-2 ring-n-amber-6'
          : 'bg-n-blue-2 ring-n-blue-6'
      "
    >
      <span class="flex items-center gap-3 text-sm text-n-slate-12">
        <span
          class="size-5 flex-none"
          :class="
            pending === 'broken'
              ? 'i-lucide-unplug text-n-amber-11'
              : 'i-lucide-hourglass text-n-blue-11'
          "
          aria-hidden="true"
        />
        {{ $t(`${SEM_LOGIN}.PENDING.${pending.toUpperCase()}.TEXT`) }}
      </span>
      <button
        type="button"
        data-anuncios-conexao-continuar
        class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-semibold text-n-slate-12 ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="connecting = true"
      >
        {{ $t(`${SEM_LOGIN}.PENDING.${pending.toUpperCase()}.CTA`) }}
        <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
      </button>
    </div>

    <AnunciosVazio
      v-if="screen === 'ready'"
      :inboxes="result.official_inboxes || []"
      :can-connect="!readOnly && !pending"
      @example="example = true"
      @connect="connecting = true"
    />

    <template v-else-if="screen === 'example'">
      <div
        data-anuncios-exemplo
        class="flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-n-amber-2 p-4 ring-1 ring-inset ring-n-amber-6"
      >
        <span class="flex flex-wrap items-center gap-3">
          <span
            data-anuncios-exemplo-selo
            class="inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4 bg-n-amber-4 text-n-amber-12"
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
          class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="example = false"
        >
          <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
          {{ $t(`${SEM_LOGIN}.EXAMPLE.BACK`) }}
        </button>
      </div>
      <MetaAdsPanel :sample="sample" read-only />
    </template>

    <ConectarAnuncios
      v-else-if="screen === 'connect'"
      :connection="connection"
      :resume="resume"
      @back="closeConnect"
      @connected="emit('connected')"
    />

    <MetaAdsPanel v-else :read-only="readOnly" @connect="connecting = true" />
  </div>
</template>
