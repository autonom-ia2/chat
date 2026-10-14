<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import FunilResumoCartao from './FunilResumoCartao.vue';
import FunilEtapaLinha from './FunilEtapaLinha.vue';
import FunilCartaoVendas from './FunilCartaoVendas.vue';
import FunilCartaoQuandoUsar from './FunilCartaoQuandoUsar.vue';

// #1384 — Criar, último passo: o funil em frases antes de criar. Nada novo é
// pedido aqui; cada parte tem "Alterar".
const props = defineProps({
  nome: { type: String, default: '' },
  etapas: { type: Array, required: true },
  semFrase: { type: Array, default: () => [] },
  quandoUsar: { type: String, default: '' },
  venda: { type: Boolean, default: true },
  meta: { type: [String, Number], default: '' },
  dinheiro: { type: Function, required: true },
  ia: { type: Boolean, default: false },
  sucesso: { type: String, default: '' },
  fracasso: { type: String, default: '' },
});

defineEmits(['etapas', 'abrir', 'alterarEtapa', 'criar']);

const { t } = useI18n();
const primeira = computed(() => props.etapas[0]?.name || '');
const ultima = computed(() => props.etapas.at(-1)?.name || '');
const acontece = computed(() => [
  t('CRM_FUNIL.CONFIRA.ACONTECE_1', {
    nome: props.nome.trim(),
    n: props.etapas.length,
  }),
  ...(props.ia ? [t('CRM_FUNIL.CONFIRA.ACONTECE_2')] : []),
  t(
    props.venda
      ? 'CRM_FUNIL.CONFIRA.ACONTECE_3'
      : 'CRM_FUNIL.CONFIRA.ACONTECE_3_ATENDER'
  ),
]);
</script>

<template>
  <header class="flex flex-col gap-1">
    <h3 class="mb-0 text-xl font-semibold text-n-slate-12">
      {{ $t('CRM_FUNIL.CONFIRA.TITULO') }}
    </h3>
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{
        $t(
          semFrase.length
            ? 'CRM_FUNIL.CONFIRA.FALTA_POUCO'
            : 'CRM_FUNIL.CONFIRA.TUDO_PRONTO'
        )
      }}
    </p>
  </header>
  <FunilResumoCartao
    parte="stages"
    icone="i-lucide-columns-3"
    :titulo="$t('CRM_FUNIL.ETAPAS.ROTULO')"
    @alterar="$emit('etapas')"
  >
    <I18nT keypath="CRM_FUNIL.CONFIRA.FRASE" tag="span" scope="global">
      <template #etapas>
        <strong class="font-semibold">
          {{
            $t('CRM_FUNIL.CONFIRA.ETAPAS', { n: etapas.length }, etapas.length)
          }}
        </strong>
      </template>
      <template #primeira>
        <strong class="font-semibold">{{ primeira }}</strong>
      </template>
      <template #ultima>
        <strong class="font-semibold">{{ ultima }}</strong>
      </template>
    </I18nT>
  </FunilResumoCartao>
  <FunilEtapaLinha
    v-for="etapa in semFrase"
    :key="etapa.editorKey"
    :nome="etapa.name"
    :cor="etapa.color"
    :numero="etapas.indexOf(etapa) + 1"
    frase=""
    ia
    @alterar="$emit('alterarEtapa', etapa)"
    @criar="$emit('criar', etapa)"
  />
  <FunilCartaoQuandoUsar
    :texto="quandoUsar"
    @alterar="$emit('abrir', 'about')"
  />
  <FunilCartaoVendas
    :venda="venda"
    :meta="meta"
    :dinheiro="dinheiro"
    :sucesso="sucesso"
    :fracasso="fracasso"
    @alterar="$emit('abrir', 'sales')"
  />
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-blue-7 bg-n-blue-2 p-5"
  >
    <h4 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ $t('CRM_FUNIL.CONFIRA.ACONTECE') }}
    </h4>
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="frase in acontece"
        :key="frase"
        class="flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
      >
        <span
          class="i-lucide-arrow-right mt-1 size-4 shrink-0 text-n-blue-11 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ frase }}
      </li>
    </ul>
  </section>
</template>
