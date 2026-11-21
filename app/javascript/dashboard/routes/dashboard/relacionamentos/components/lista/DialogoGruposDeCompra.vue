<script setup>
import { computed, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { FAIXAS_PADRAO } from '../../fonte/gruposDeCompra';

// #3097 — "Ajustar os grupos": as quatro faixas dos grupos de compra, cada uma
// numa frase com o número ao lado ("Começa a contar como sem comprar depois de
// [90] dias"). Salvar só vai com os números certos (maiores que zero, o último
// grupo depois do primeiro e o campeão antes de "sem comprar"); o erro aparece
// embaixo do campo. "Voltar ao
// padrão" só preenche: nada grava antes de Salvar. Mudar as faixas não dispara
// automação (o servidor só dispara o "entrou no grupo" por venda ou pelo
// tempo), e o diálogo diz isso. Quem salva é a página
// (`salvar` devolve se gravou).
const props = defineProps({
  faixas: { type: Object, required: true },
  salvar: { type: Function, required: true },
});
const emit = defineEmits(['salvo']);

const { t } = useI18n();
const AJ = 'RELACIONAMENTOS_COMPRAS.AJUSTE';
const idBase = useId();
const dialogo = useTemplateRef('dialogo');
const rascunho = ref({ ...FAIXAS_PADRAO });
const salvando = ref(false);
const tentou = ref(false);

const CAMPOS = [
  { chave: 'campeao_compras', antes: 'CAMPEAO_COMPRAS', depois: 'VEZES' },
  { chave: 'campeao_dias', antes: 'CAMPEAO_DIAS', depois: 'DIAS' },
  { chave: 'em_risco_dias', antes: 'EM_RISCO', depois: 'DIAS' },
  { chave: 'perdido_dias', antes: 'PERDIDO', depois: 'DIAS' },
];

const numero = chave => Number(rascunho.value[chave]);
const erros = computed(() => {
  const lista = Object.fromEntries(
    CAMPOS.filter(({ chave }) => !(numero(chave) > 0)).map(({ chave }) => [
      chave,
      t(`${AJ}.ERRO_MINIMO`),
    ])
  );
  if (
    !lista.perdido_dias &&
    numero('perdido_dias') <= numero('em_risco_dias')
  ) {
    lista.perdido_dias = t(`${AJ}.ERRO_ORDEM`, {
      dias: numero('em_risco_dias'),
    });
  }
  // Com o campeão de 120 dias e "sem comprar" em 90, ninguém vira campeão.
  if (
    !lista.campeao_dias &&
    numero('campeao_dias') >= numero('em_risco_dias')
  ) {
    lista.campeao_dias = t(`${AJ}.ERRO_CAMPEAO`, {
      dias: numero('em_risco_dias'),
    });
  }
  return lista;
});
const erroDe = chave => (tentou.value ? erros.value[chave] || '' : '');

const abrir = () => {
  rascunho.value = { ...props.faixas };
  tentou.value = false;
  dialogo.value?.open();
};
const voltarAoPadrao = () => {
  rascunho.value = { ...FAIXAS_PADRAO };
};
const confirmar = async () => {
  tentou.value = true;
  if (Object.keys(erros.value).length) return;
  salvando.value = true;
  const novas = Object.fromEntries(
    CAMPOS.map(({ chave }) => [chave, numero(chave)])
  );
  const gravou = await props.salvar(novas);
  salvando.value = false;
  if (!gravou) return;
  dialogo.value?.close();
  emit('salvo');
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="t(`${AJ}.SALVAR`)"
    :cancel-button-label="t(`${AJ}.CANCELAR`)"
    :is-loading="salvando"
    @confirm="confirmar"
  >
    <TituloDoDialogo
      :titulo="t(`${AJ}.TITULO`)"
      :aviso="t(`${AJ}.EXPLICACAO`)"
    />
    <div
      data-relacionamentos="dialogo-grupos-de-compra"
      class="flex flex-col gap-5"
    >
      <div
        v-for="campo in CAMPOS"
        :key="campo.chave"
        class="flex flex-col gap-2"
      >
        <label
          :for="`${idBase}-${campo.chave}`"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t(`${AJ}.${campo.antes}`) }}
        </label>
        <div class="flex items-start gap-3">
          <Input
            :id="`${idBase}-${campo.chave}`"
            v-model="rascunho[campo.chave]"
            type="number"
            min="1"
            class="w-28 shrink-0"
            :message="erroDe(campo.chave)"
            :message-type="erroDe(campo.chave) ? 'error' : 'info'"
            wrap-message
          />
          <span class="text-base leading-10 text-n-slate-11">
            {{ t(`${AJ}.${campo.depois}`) }}
          </span>
        </div>
      </div>
      <p
        data-relacionamentos="nao-dispara"
        class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
      >
        <span
          class="i-lucide-shield-check mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ t(`${AJ}.NAO_DISPARA`) }}
      </p>
      <Button
        slate
        link
        class="self-start min-h-11"
        :label="t(`${AJ}.PADRAO`)"
        @click="voltarAoPadrao"
      />
    </div>
  </Dialog>
</template>
