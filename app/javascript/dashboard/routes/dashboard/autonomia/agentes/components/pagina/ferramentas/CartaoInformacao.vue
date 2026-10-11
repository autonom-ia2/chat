<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaInterruptor from './FerramentaInterruptor.vue';
import { TIPOS } from '../../../utils/ferramentas';

// #1301 (protótipo F05) — uma informação que o agente preenche: nome, tipo em português (escolha do
// produto, sem <select>), como o agente descobre e "Pode faltar". "Remover" é discreto: neutro,
// rubi só no hover/foco, alvo de 44 px.
const props = defineProps({
  informacao: { type: Object, required: true },
  indice: { type: Number, required: true },
  base: { type: String, required: true },
  erro: { type: String, default: '' },
});

const emit = defineEmits(['update:informacao', 'remover']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.TRES';
const { t } = useI18n();

const id = computed(() => `${props.base}-info-${props.indice}`);
const preenchido = valor => String(valor ?? '').trim() !== '';
const quem = computed(() =>
  preenchido(props.informacao.nome)
    ? props.informacao.nome
    : t(`${NS}.ITEM`, { n: props.indice + 1 })
);
const tipos = computed(() =>
  TIPOS.map(tipo => ({ value: tipo, label: t(`${NS}.TIPOS.${tipo}`) }))
);

const mudar = (campo, valor) =>
  emit('update:informacao', { ...props.informacao, [campo]: valor });
</script>

<template>
  <div
    :data-informacao="indice"
    role="group"
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-4 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex items-center justify-between gap-2">
      <p
        :id="`${id}-titulo`"
        class="m-0 text-sm font-semibold break-all text-n-slate-12"
        :class="preenchido(informacao.nome) ? 'font-mono' : ''"
      >
        {{ preenchido(informacao.nome) ? informacao.nome : t(`${NS}.NOVA`) }}
      </p>
      <button
        type="button"
        data-remover
        :aria-label="
          t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.REMOVER_SR', { item: quem })
        "
        class="inline-flex items-center gap-1.5 px-2 text-sm rounded-lg min-h-11 shrink-0 text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-alpha-2 focus-visible:text-n-ruby-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('remover')"
      >
        <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
        {{ t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.REMOVER') }}
      </button>
    </div>
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <FerramentaCampo
        :id="`${id}-nome`"
        :rotulo="t(`${NS}.NOME`)"
        :erro="erro"
      >
        <template #default="{ descricao, invalido }">
          <FerramentaEntrada
            :id="`${id}-nome`"
            data-campo-informacao
            :model-value="informacao.nome"
            mono
            :placeholder="t(`${NS}.ITEM`, { n: indice + 1 })"
            :descricao="descricao"
            :invalido="invalido"
            @update:model-value="mudar('nome', $event)"
          />
        </template>
      </FerramentaCampo>
      <div class="flex flex-col min-w-0 gap-1.5">
        <label
          :for="`${id}-tipo`"
          class="text-sm font-semibold text-n-slate-12"
        >
          {{ t(`${NS}.TIPO`) }}
        </label>
        <ChoiceSelect
          :model-value="informacao.tipo"
          :trigger-id="`${id}-tipo`"
          :options="tipos"
          :aria-label="t(`${NS}.TIPO`)"
          class="w-full"
          @update:model-value="mudar('tipo', $event)"
        />
      </div>
    </div>
    <FerramentaCampo
      :id="`${id}-descricao`"
      :rotulo="t(`${NS}.DESCRICAO`)"
      :ajuda="t(`${NS}.DESCRICAO_AJUDA`)"
      :exemplo="t(`${NS}.DESCRICAO_EXEMPLO`)"
      :preenchido="preenchido(informacao.descricao)"
    >
      <template #default="{ descricao }">
        <FerramentaEntrada
          :id="`${id}-descricao`"
          :model-value="informacao.descricao"
          :linhas="3"
          :descricao="descricao"
          @update:model-value="mudar('descricao', $event)"
        />
      </template>
    </FerramentaCampo>
    <div class="flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <FerramentaInterruptor
          data-pode-faltar
          :ligado="informacao.podeFaltar"
          :rotulo="t(`${NS}.PODE_FALTAR_SR`, { item: quem })"
          @alternar="mudar('podeFaltar', $event)"
        />
        <span aria-hidden="true" class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.PODE_FALTAR`) }}
        </span>
      </div>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          informacao.podeFaltar
            ? t(`${NS}.PODE_FALTAR_SIM`)
            : t(`${NS}.PODE_FALTAR_NAO`)
        }}
      </p>
    </div>
  </div>
</template>
