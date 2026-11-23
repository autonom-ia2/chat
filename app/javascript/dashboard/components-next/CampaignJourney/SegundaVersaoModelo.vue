<script setup>
// #3099 — no WhatsApp Oficial, cada versão é um modelo aprovado pelo WhatsApp. A versão 2 é outro modelo da mesma caixa,
// que pede as mesmas informações da versão 1 (assim as escolhas de "de onde vem cada informação" valem para as duas).
// O modelo da versão 1 e os que pedem outras informações aparecem apagados, com o motivo. Sem outro modelo que sirva,
// a saída é criar um (o mesmo caminho da ponte de Modelos do WhatsApp, que quem chama abre).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  // [{ value, label, corpo (já com o exemplo do primeiro cliente), mesmasInformacoes }] — os aprovados da caixa.
  modelos: { type: Array, default: () => [] },
  primeiraId: { type: [String, Number], default: null },
  templateId: { type: [String, Number], default: null },
});
const emit = defineEmits(['update', 'criar']);

const NS = 'DUAS_VERSOES.MODELO';
const { t } = useI18n();

const ehAPrimeira = modelo => String(modelo.value) === String(props.primeiraId);
const opcoes = computed(() =>
  props.modelos.map(modelo => {
    let hint = '';
    if (ehAPrimeira(modelo)) hint = t(`${NS}.JA_E_A_1`);
    else if (!modelo.mesmasInformacoes) hint = t(`${NS}.OUTRAS_INFORMACOES`);
    return {
      value: modelo.value,
      label: modelo.label,
      disabled: Boolean(hint),
      hint,
    };
  })
);
const temOutro = computed(() => opcoes.value.some(opcao => !opcao.disabled));
const corpoDe = id =>
  props.modelos.find(modelo => String(modelo.value) === String(id))?.corpo ||
  '';
const versoes = computed(() => [
  { numero: 1, corpo: corpoDe(props.primeiraId) },
  { numero: 2, corpo: corpoDe(props.templateId) },
]);
</script>

<template>
  <div
    class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start"
    data-segunda-versao-modelo
  >
    <div class="flex min-w-0 flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.ROTULO`) }}
      </span>
      <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.AJUDA`) }}</p>
      <ChoiceSelect
        v-if="temOutro"
        :model-value="templateId ?? ''"
        :options="opcoes"
        :aria-label="t(`${NS}.ROTULO`)"
        :placeholder="t(`${NS}.PLACEHOLDER`)"
        data-modelo-da-2
        @update:model-value="id => emit('update', id)"
      />
      <div
        v-else
        class="flex flex-col items-start gap-3 rounded-xl bg-n-amber-2 px-4 py-3"
        role="status"
        data-sem-outro-modelo
      >
        <p class="m-0 text-sm text-n-amber-12">{{ t(`${NS}.SEM_OUTRO`) }}</p>
        <Button
          :label="t(`${NS}.CRIAR`)"
          icon="i-lucide-plus"
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11 !rounded-xl bg-n-solid-1"
          @click="emit('criar')"
        />
      </div>
    </div>

    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
      data-como-chega
    >
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.COMO_FICA`) }}
      </h3>
      <div
        v-for="versao in versoes"
        :key="versao.numero"
        class="flex flex-col gap-1.5 rounded-2xl bg-n-teal-2 p-3"
        :data-previa-versao="versao.numero"
      >
        <span class="text-xs font-semibold text-n-slate-11">
          {{ t('DUAS_VERSOES.MENSAGEM.VERSAO', { n: versao.numero }) }}
        </span>
        <p
          v-if="versao.corpo"
          class="m-0 max-w-xs whitespace-pre-wrap rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
        >
          {{ versao.corpo }}
        </p>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.AINDA_VAZIA`) }}
        </p>
      </div>
    </aside>
  </div>
</template>
