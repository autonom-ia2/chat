<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CaixaIcone from '../../caixas/components/CaixaIcone.vue';

// #1149 (R16) — o funil só mostra onde está ligado. Ligar, desligar e escolher
// como o card nasce ficam num lugar só: Caixas no CRM, com um único Salvar.
// Cada caixa leva direto à página dela lá.
const props = defineProps({
  caixas: { type: Array, default: () => [] },
  ligadas: { type: Array, default: () => [] },
  etapas: { type: Array, default: () => [] },
  carregando: { type: Boolean, default: false },
});

// O caminho em destaque, para a prévia mostrar onde a conversa cai.
const foco = defineModel('foco', { type: Object, default: null });

const { t } = useI18n();

// As etapas salvas do funil. Sem etapa escolhida, o card nasce na primeira por
// posição e id, como o Crm::Conversations::CardSyncer.
const primeiraEtapa = computed(
  () =>
    [...props.etapas].sort(
      (a, b) => a.position - b.position || Number(a.id) - Number(b.id)
    )[0] || null
);
const etapaPorId = id =>
  props.etapas.find(etapa => Number(etapa.id) === Number(id)) ||
  primeiraEtapa.value;

const cartoes = computed(() =>
  props.ligadas.map(ligada => {
    const caixa = props.caixas.find(
      item => Number(item.id) === Number(ligada.inbox_id)
    );
    return {
      id: ligada.inbox_id,
      nome: ligada.inbox?.name || caixa?.name || '',
      canal: ligada.inbox?.channel_type || caixa?.channel_type,
      etapa: ligada.auto_create_card
        ? etapaPorId(ligada.default_stage_id)
        : null,
    };
  })
);

watch(
  cartoes,
  lista => {
    const primeira = lista.find(cartao => cartao.etapa);
    foco.value = primeira
      ? { nome: primeira.nome, etapa: primeira.etapa, sozinho: true }
      : null;
  },
  { immediate: true }
);

// O nome da tela de caixas sai de uma chave só (o título dela).
const lugar = computed(() => t('CRM_CAIXAS.LISTA.TITULO'));

const frase = cartao =>
  cartao.etapa
    ? t('CRM_FUNIL.CAIXAS.SOZINHO')
    : t('CRM_FUNIL.CAIXAS.ESCOLHIDO');
</script>

<template>
  <div data-funil-caixas class="flex flex-col gap-4">
    <p
      v-if="carregando"
      class="mb-0 rounded-2xl bg-n-alpha-2 p-5 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('CRM_KANBAN.PIPELINE_DRAWER.LOADING_INBOXES') }}
    </p>
    <p
      v-else-if="!cartoes.length"
      class="mb-0 rounded-2xl border border-dashed border-n-slate-6 p-5 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('CRM_FUNIL.RESUMO.CAIXAS_NENHUMA') }}
    </p>
    <template v-else>
      <h4 class="mb-0 text-sm font-medium text-n-slate-11">
        {{ $t('CRM_FUNIL.CAIXAS.LIGADO_EM') }}
      </h4>
      <article
        v-for="cartao in cartoes"
        :key="cartao.id"
        :data-caixa="cartao.nome"
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <header class="flex items-start gap-3">
          <CaixaIcone :canal="cartao.canal" :caixa-id="cartao.id" />
          <h5
            class="mb-0 min-w-0 flex-1 truncate pt-2 text-base font-semibold text-n-slate-12"
          >
            {{ cartao.nome }}
          </h5>
        </header>
        <p
          v-if="cartao.etapa"
          class="mb-0 flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-12"
        >
          {{ $t('CRM_FUNIL.CAIXAS.CONVERSA_NOVA') }}
          <span
            class="i-lucide-arrow-right size-4 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
          <span
            class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-sm font-medium"
          >
            <span
              class="size-2.5 rounded-full"
              :style="{ backgroundColor: cartao.etapa.color }"
              aria-hidden="true"
            />
            {{ cartao.etapa.name }}
          </span>
        </p>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ frase(cartao) }}
        </p>
        <router-link
          :to="{ name: 'crm_caixa', params: { inboxId: cartao.id } }"
          :aria-label="
            $t('CRM_FUNIL.CAIXAS.MUDAR_NOME', { nome: cartao.nome, lugar })
          "
          class="inline-flex min-h-11 w-fit items-center gap-2 rounded-xl px-1 text-[0.9375rem] font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ $t('CRM_FUNIL.CAIXAS.MUDAR', { lugar }) }}
          <span
            class="i-lucide-arrow-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </router-link>
      </article>
    </template>
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('CRM_FUNIL.CAIXAS.ONDE_MUDA', { lugar }) }}
    </p>
    <router-link
      :to="{ name: 'crm_caixas' }"
      class="inline-flex min-h-11 w-fit items-center gap-2 rounded-xl px-1 text-[0.9375rem] font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      {{ $t('CRM_FUNIL.CAIXAS.ABRIR_CAIXAS', { lugar }) }}
      <span
        class="i-lucide-arrow-right size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </router-link>
  </div>
</template>
