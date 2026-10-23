<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import {
  abaDoDesfecho,
  desfechoDe,
  quemArquivou,
  seloDoDesfecho,
  valorDaLinha,
} from './textosDoArquivado';

// Uma linha de Arquivados (#2095): quem, quando e por quê; onde o card volta ao restaurar (o fechado vai para a
// Lista, não para o quadro, e a linha avisa antes do clique); e o card guardado num funil arquivado, que só volta
// com o funil. O slot `acoes` deixa outra parte acrescentar um botão (ex.: Excluir de vez).
const props = defineProps({
  linha: { type: Object, required: true },
  // O funil do card, quando ele está entre os ativos (dá os nomes dos desfechos).
  funil: { type: Object, default: null },
  formato: { type: Object, required: true },
  podeArquivar: { type: Boolean, default: false },
  mostraFunil: { type: Boolean, default: false },
  selecionavel: { type: Boolean, default: false },
  selecionado: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  erro: { type: String, default: '' },
});
const emit = defineEmits([
  'abrir',
  'restaurar',
  'selecionar',
  'verFunisArquivados',
]);

const { t } = useI18n();

const funilArquivado = computed(
  () => props.linha.pipeline?.status === 'archived'
);
// Card que não foi arquivado sozinho: ficou no funil quando o funil foi arquivado.
const guardadoComOFunil = computed(
  () => funilArquivado.value && props.linha.status !== 'archived'
);
const desfecho = computed(() => desfechoDe(props.linha));
const selo = computed(() =>
  desfecho.value ? seloDoDesfecho(t, desfecho.value, props.funil) : null
);
const valor = computed(() => valorDaLinha(t, props.formato, props.linha));
const etapa = computed(() => props.linha.stage?.name || '');
const resumo = computed(() => {
  const partes = [];
  if (valor.value) partes.push(valor.value);
  if (props.mostraFunil && props.linha.pipeline?.name) {
    partes.push(
      funilArquivado.value
        ? t('CRM_ARQUIVADOS.LINHA.FUNIL_ARQUIVADO', {
            funil: props.linha.pipeline.name,
          })
        : props.linha.pipeline.name
    );
  }
  if (etapa.value)
    partes.push(t('CRM_ARQUIVADOS.LINHA.ESTAVA_EM', { etapa: etapa.value }));
  return partes.join(' · ');
});
const quando = computed(() =>
  guardadoComOFunil.value
    ? t('CRM_ARQUIVADOS.LINHA.GUARDADO_COM_O_FUNIL')
    : quemArquivou(t, props.formato, props.linha)
);
const dica = computed(() => {
  if (funilArquivado.value)
    return t('CRM_ARQUIVADOS.LINHA.DICA_FUNIL_ARQUIVADO', {
      funil: props.linha.pipeline?.name || '',
    });
  const aba = abaDoDesfecho(t, desfecho.value, props.funil);
  return aba ? t('CRM_ARQUIVADOS.LINHA.DICA_FECHADO', { aba }) : '';
});
const podeRestaurar = computed(
  () =>
    props.podeArquivar &&
    !funilArquivado.value &&
    props.linha.can_restore !== false
);
const iniciais = computed(() =>
  String(props.linha.title || '?')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase()
);
</script>

<template>
  <li
    data-arquivado-linha
    :data-card-id="linha.id"
    class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-n-weak py-3 last:border-b-0"
  >
    <label
      v-if="selecionavel"
      class="grid size-11 shrink-0 cursor-pointer place-items-center rounded-lg hover:bg-n-alpha-2"
    >
      <span class="sr-only">{{
        t('CRM_ARQUIVADOS.SELECIONAR_UM', { nome: linha.title })
      }}</span>
      <Checkbox
        :model-value="selecionado"
        data-arquivado-selecionar
        @change="emit('selecionar', linha.id)"
      />
    </label>
    <button
      type="button"
      data-arquivado-abrir
      class="flex min-h-11 min-w-0 flex-1 basis-56 items-start gap-3 rounded-lg p-1 text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
      @click="emit('abrir', linha)"
    >
      <span
        aria-hidden="true"
        class="grid size-10 shrink-0 place-items-center rounded-full bg-n-alpha-2 text-sm font-semibold text-n-slate-11"
      >
        {{ iniciais }}
      </span>
      <span class="min-w-0">
        <span class="flex flex-wrap items-center gap-2">
          <span class="font-medium text-n-slate-12">{{ linha.title }}</span>
          <span
            v-if="selo"
            data-arquivado-selo
            class="rounded-full px-2 py-0.5 text-xs font-medium"
            :class="selo.classe"
          >
            {{ selo.rotulo }}
          </span>
        </span>
        <span v-if="resumo" class="block text-sm text-n-slate-11">
          {{ resumo }}
        </span>
        <span
          v-if="quando"
          data-arquivado-quando
          class="block text-xs text-n-slate-11"
        >
          {{ quando }}
        </span>
        <span
          v-if="dica"
          data-arquivado-dica
          class="block text-xs text-n-slate-11"
        >
          {{ dica }}
        </span>
      </span>
    </button>
    <div class="flex flex-wrap items-center gap-2">
      <Button
        v-if="funilArquivado"
        :label="t('CRM_ARQUIVADOS.VER_FUNIS_ARQUIVADOS')"
        icon="i-lucide-archive"
        slate
        faded
        class="!min-h-11"
        @click="emit('verFunisArquivados')"
      />
      <Button
        v-else-if="podeRestaurar"
        data-arquivado-restaurar
        :label="t('CRM_ARQUIVADOS.RESTAURAR')"
        icon="i-lucide-rotate-ccw"
        slate
        faded
        class="!min-h-11"
        :is-loading="ocupado"
        :disabled="ocupado"
        @click="emit('restaurar', linha)"
      />
      <slot name="acoes" :linha="linha" :funil-arquivado="funilArquivado" />
    </div>
    <p
      v-if="erro"
      role="alert"
      data-arquivado-erro
      class="mb-0 basis-full rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
    >
      {{ erro }}
    </p>
  </li>
</template>
