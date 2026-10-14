<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CaixaIcone from '../../caixas/components/CaixaIcone.vue';
import FunilInterruptor from './FunilInterruptor.vue';

// #1384 — por onde os clientes chegam. Cada caixa de entrada (um WhatsApp, o
// Instagram, o chat do site) é um cartão como em "Caixas no CRM": a que já
// traz conversas mostra o caminho "Conversa nova → coluna"; a outra se liga
// ali mesmo. Ligar e desligar salvam na hora.
const props = defineProps({
  caixas: { type: Array, default: () => [] },
  ligadas: { type: Array, default: () => [] },
  etapas: { type: Array, default: () => [] },
  carregando: { type: Boolean, default: false },
  salvando: { type: Boolean, default: false },
  removendo: { type: Boolean, default: false },
});

const emit = defineEmits(['ligar', 'desligar']);

// O caminho em destaque, para a prévia mostrar onde a conversa cai.
const foco = defineModel('foco', { type: Object, default: null });
// Enquanto uma caixa está sendo ligada, "Ligar esta caixa" é a única ação
// principal: a gaveta apaga o "Pronto" do rodapé.
const aberta = defineModel('aberta', { type: Boolean, default: false });

const { t } = useI18n();

const etapaPorId = id =>
  props.etapas.find(etapa => Number(etapa.id) === Number(id)) ||
  props.etapas[0];

const cartoes = computed(() =>
  props.caixas.map(caixa => {
    const ligada = props.ligadas.find(
      item => Number(item.inbox_id) === Number(caixa.id)
    );
    return {
      id: caixa.id,
      nome: caixa.name,
      canal: caixa.channel_type,
      ligada,
      etapa: ligada ? etapaPorId(ligada.default_stage_id) : null,
      sozinho: ligada ? ligada.auto_create_card : true,
    };
  })
);

const abrindo = ref(null);
const nova = ref({ etapaId: '', sozinho: true });
const opcoesEtapa = computed(() =>
  props.etapas.map(etapa => ({ value: etapa.id, label: etapa.name }))
);

const abrir = cartao => {
  abrindo.value = cartao.id;
  nova.value = { etapaId: props.etapas[0]?.id ?? '', sozinho: true };
};

watch(
  () => props.ligadas.length,
  () => {
    abrindo.value = null;
  }
);
watch(
  abrindo,
  valor => {
    aberta.value = valor !== null;
  },
  { immediate: true }
);

const ligar = cartao => {
  emit('ligar', {
    inbox_id: cartao.id,
    default_stage_id: nova.value.etapaId || null,
    auto_create_card: nova.value.sozinho,
  });
};

watch(
  [cartoes, abrindo, nova],
  () => {
    const aberto = cartoes.value.find(cartao => cartao.id === abrindo.value);
    if (aberto && !aberto.ligada) {
      foco.value = {
        nome: aberto.nome,
        etapa: etapaPorId(nova.value.etapaId),
        sozinho: nova.value.sozinho,
      };
      return;
    }
    const primeira = cartoes.value.find(cartao => cartao.ligada);
    foco.value = primeira
      ? {
          nome: primeira.nome,
          etapa: primeira.etapa,
          sozinho: primeira.sozinho,
        }
      : null;
  },
  { immediate: true, deep: true }
);

// "Traz conversas", "Ligando…" (formulário aberto) ou "Não traz".
const estado = cartao => {
  if (cartao.ligada)
    return {
      chave: 'CRM_FUNIL.CAIXAS.TRAZ',
      texto: 'text-n-teal-11',
      ponto: 'bg-n-teal-9',
    };
  if (abrindo.value === cartao.id)
    return {
      chave: 'CRM_FUNIL.CAIXAS.LIGANDO',
      texto: 'text-n-blue-11',
      ponto: 'bg-n-blue-9',
    };
  return {
    chave: 'CRM_FUNIL.CAIXAS.NAO_TRAZ',
    texto: 'text-n-slate-11',
    ponto: 'bg-n-slate-8',
  };
};

const frase = cartao =>
  t(cartao.sozinho ? 'CRM_FUNIL.CAIXAS.SOZINHO' : 'CRM_FUNIL.CAIXAS.EQUIPE');
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
      {{ $t('CRM_FUNIL.CAIXAS.NENHUMA') }}
    </p>
    <template v-else>
      <article
        v-for="cartao in cartoes"
        :key="cartao.id"
        :data-caixa="cartao.nome"
        class="flex flex-col gap-4 rounded-2xl border bg-n-solid-1 p-5"
        :class="
          cartao.ligada
            ? 'border-n-teal-7'
            : abrindo === cartao.id
              ? 'border-n-blue-7'
              : 'border-n-weak'
        "
      >
        <header class="flex items-start gap-3">
          <CaixaIcone :canal="cartao.canal" />
          <div class="min-w-0 flex-1">
            <h4 class="mb-1 truncate text-base font-semibold text-n-slate-12">
              {{ cartao.nome }}
            </h4>
            <span
              class="inline-flex items-center gap-1.5 text-sm"
              :class="estado(cartao).texto"
            >
              <span
                class="size-2 rounded-full"
                :class="estado(cartao).ponto"
                aria-hidden="true"
              />
              {{ $t(estado(cartao).chave) }}
            </span>
          </div>
          <Button
            v-if="cartao.ligada"
            :label="$t('CRM_FUNIL.CAIXAS.DESLIGAR')"
            :aria-label="
              $t('CRM_FUNIL.CAIXAS.DESLIGAR_NOME', { nome: cartao.nome })
            "
            slate
            faded
            class="!min-h-11 shrink-0"
            :is-loading="removendo"
            :disabled="removendo || salvando"
            @click="emit('desligar', cartao.ligada)"
          />
          <Button
            v-else-if="abrindo !== cartao.id"
            :label="$t('CRM_FUNIL.CAIXAS.LIGAR')"
            icon="i-lucide-plus"
            blue
            faded
            class="!min-h-11 shrink-0"
            @click="abrir(cartao)"
          />
        </header>

        <div v-if="cartao.ligada" class="flex flex-col gap-2">
          <p
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
                :style="{ backgroundColor: cartao.etapa?.color }"
                aria-hidden="true"
              />
              {{ cartao.etapa?.name }}
            </span>
          </p>
          <p class="mb-0 text-[0.9375rem] text-n-slate-11">
            {{ frase(cartao) }}
          </p>
        </div>

        <div
          v-else-if="abrindo === cartao.id"
          class="flex flex-col gap-4 border-t border-n-weak pt-4"
        >
          <div class="flex flex-col gap-1">
            <span
              id="funil-caixa-coluna"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ $t('CRM_FUNIL.CAIXAS.COMECA') }}
            </span>
            <ChoiceSelect
              v-model="nova.etapaId"
              :options="opcoesEtapa"
              :aria-label="$t('CRM_FUNIL.CAIXAS.COMECA')"
              class="max-w-xs"
            />
          </div>
          <label
            class="flex cursor-pointer items-center justify-between gap-4 rounded-xl bg-n-alpha-2 px-4 py-1"
          >
            <span class="text-[0.9375rem] text-n-slate-12">
              {{ $t('CRM_FUNIL.CAIXAS.CRIAR_SOZINHO') }}
            </span>
            <FunilInterruptor v-model="nova.sozinho" />
          </label>
          <div class="flex flex-wrap gap-2">
            <Button
              data-caixa-ligar
              :label="$t('CRM_FUNIL.CAIXAS.LIGAR_ESTA')"
              icon="i-lucide-check"
              class="!min-h-11"
              :is-loading="salvando"
              :disabled="salvando || removendo"
              @click="ligar(cartao)"
            />
            <Button
              :label="$t('CRM_FUNIL.CANCELAR')"
              slate
              ghost
              class="!min-h-11"
              @click="abrindo = null"
            />
          </div>
        </div>
      </article>
    </template>
    <router-link
      :to="{ name: 'crm_caixas' }"
      class="inline-flex min-h-11 w-fit items-center gap-2 rounded-xl px-1 text-[0.9375rem] font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      {{ $t('CRM_FUNIL.CAIXAS.QUEM_ATENDE') }}
      <span
        class="i-lucide-arrow-right size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </router-link>
  </div>
</template>
