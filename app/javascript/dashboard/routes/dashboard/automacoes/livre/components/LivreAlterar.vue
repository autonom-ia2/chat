<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreCampo from './LivreCampo.vue';
import {
  FREIO_PADRAO,
  PADROES_DE_GATILHO,
  TIPOS_DE_GATILHO,
  TIPOS_DE_META,
  TIPOS_DE_PASSO,
} from '../prototipo/catalogo';
import { fraseDaMeta, fraseDoGatilho, fraseDoPasso } from '../prototipo/frases';
import { copiar, passoSemVolta } from '../prototipo/receita';

// #2414 F0 — o painel do "Alterar": mostra os campos do item escolhido (passo,
// gatilho, condição, meta ou freio), já preenchidos. Nada muda até "Salvar".
const emit = defineEmits(['salvar', 'tirar', 'close']);

const { t } = useI18n();
const painel = ref(null);
const idTipo = useId();

// { tipo: 'passo'|'gatilho'|'condicao'|'meta'|'freio', indice?, valor }
const alvo = ref(null);
const rascunho = ref(null);

const CAMPOS_DO_FREIO = [
  'nao_repetir_dias',
  'por_hora',
  'mensagem_minutos',
  'ia_por_dia',
];

const campos = computed(() => {
  if (!alvo.value) return [];
  if (alvo.value.tipo === 'passo')
    return TIPOS_DE_PASSO[rascunho.value.tipo]?.campos || [];
  if (alvo.value.tipo === 'gatilho')
    return (
      TIPOS_DE_GATILHO.find(item => item.tipo === rascunho.value?.tipo)
        ?.campos || []
    );
  if (alvo.value.tipo === 'condicao')
    return [{ nome: 'condicao', tipo: 'condicao' }];
  return [];
});

const titulo = computed(() =>
  alvo.value
    ? t(`AUTOMACAO_LIVRE.ALTERAR_PAINEL.${alvo.value.tipo.toUpperCase()}`)
    : ''
);

const frase = computed(() => {
  if (!alvo.value || !rascunho.value) return '';
  if (alvo.value.tipo === 'passo') return fraseDoPasso(rascunho.value, t);
  if (alvo.value.tipo === 'gatilho') return fraseDoGatilho(rascunho.value, t);
  if (alvo.value.tipo === 'meta') return fraseDaMeta(rascunho.value, t);
  return '';
});

const opcoesDeGatilho = computed(() =>
  TIPOS_DE_GATILHO.map(item => ({
    value: item.tipo,
    label: fraseDoGatilho(
      { tipo: item.tipo, ...PADROES_DE_GATILHO[item.tipo] },
      t
    ),
  }))
);
const opcoesDeMeta = computed(() =>
  TIPOS_DE_META.map(tipo => ({ value: tipo, label: fraseDaMeta({ tipo }, t) }))
);

const trocarGatilho = tipo => {
  rascunho.value = { tipo, ...PADROES_DE_GATILHO[tipo] };
};
const trocarMeta = tipo => {
  rascunho.value = tipo === 'nenhuma' ? null : { tipo };
};

// O valor de um campo do rascunho; a condição usa o rascunho inteiro.
const valorDo = campo =>
  alvo.value.tipo === 'condicao' ? rascunho.value : rascunho.value[campo.nome];
const mudar = (campo, novo) => {
  rascunho.value =
    alvo.value.tipo === 'condicao'
      ? novo
      : { ...rascunho.value, [campo.nome]: novo };
};

const caminhosComRotulo = computed(() =>
  rascunho.value?.tipo === 'decisor'
    ? rascunho.value.caminhos.filter(caminho => caminho.chave !== 'nenhuma')
    : []
);
const mudarRotulo = (chave, rotulo) => {
  rascunho.value = {
    ...rascunho.value,
    caminhos: rascunho.value.caminhos.map(caminho =>
      caminho.chave === chave ? { ...caminho, rotulo } : caminho
    ),
  };
};

const freio = computed(() =>
  alvo.value?.tipo === 'freio' ? { ...FREIO_PADRAO, ...rascunho.value } : {}
);
const mudarFreio = (campo, novo) => {
  rascunho.value = { ...freio.value, [campo]: Number(novo) || 0 };
};

const abrir = item => {
  alvo.value = item;
  rascunho.value = copiar(item.valor ?? null);
  painel.value?.open();
};

const salvar = () => {
  emit('salvar', { ...alvo.value, valor: copiar(rascunho.value) });
  painel.value?.close();
};

const tirar = () => {
  emit('tirar', alvo.value);
  painel.value?.close();
};

const podeTirar = computed(() =>
  ['passo', 'condicao'].includes(alvo.value?.tipo)
);

defineExpose({ abrir });
</script>

<template>
  <SidePanel ref="painel" :title="titulo" width="lg" @close="emit('close')">
    <div v-if="alvo" data-alterar class="flex flex-col gap-5">
      <p
        v-if="frase"
        data-frase-alterar
        class="px-4 py-3 mb-0 text-base font-medium rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ frase }}
      </p>
      <p
        v-if="alvo.tipo === 'passo' && passoSemVolta(rascunho)"
        class="flex items-center gap-2 px-3 py-2 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        <span class="i-lucide-send size-4" aria-hidden="true" />
        {{ $t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA') }}
      </p>

      <div v-if="alvo.tipo === 'gatilho'" class="flex flex-col gap-1.5">
        <label :for="idTipo" class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO') }}
        </label>
        <ChoiceSelect
          :model-value="rascunho?.tipo || ''"
          :trigger-id="idTipo"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO')"
          :placeholder="$t('AUTOMACAO_LIVRE.GATILHOS.FALTA')"
          :options="opcoesDeGatilho"
          @update:model-value="trocarGatilho"
        />
      </div>

      <div v-if="alvo.tipo === 'meta'" class="flex flex-col gap-1.5">
        <label :for="idTipo" class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_META') }}
        </label>
        <ChoiceSelect
          :model-value="rascunho?.tipo || 'nenhuma'"
          :trigger-id="idTipo"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_META')"
          :options="opcoesDeMeta"
          @update:model-value="trocarMeta"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.META_DICA') }}
        </p>
      </div>

      <template v-if="rascunho && alvo.tipo !== 'freio'">
        <LivreCampo
          v-for="campo in campos"
          :key="campo.nome"
          :campo="campo"
          :model-value="valorDo(campo)"
          @update:model-value="novo => mudar(campo, novo)"
        />
      </template>

      <fieldset v-if="caminhosComRotulo.length" class="flex flex-col gap-3">
        <legend class="mb-1 text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMINHOS') }}
        </legend>
        <Input
          v-for="(caminho, indice) in caminhosComRotulo"
          :key="caminho.chave"
          :model-value="caminho.rotulo"
          :label="
            $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMINHO_N', { n: indice + 1 })
          "
          @update:model-value="rotulo => mudarRotulo(caminho.chave, rotulo)"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.NENHUMA_SEMPRE') }}
        </p>
      </fieldset>

      <div v-if="alvo.tipo === 'freio'" class="flex flex-col gap-4">
        <Input
          v-for="campo in CAMPOS_DO_FREIO"
          :key="campo"
          :model-value="String(freio[campo] || '')"
          type="number"
          min="0"
          :label="
            $t(`AUTOMACAO_LIVRE.ALTERAR_PAINEL.FREIO_${campo.toUpperCase()}`)
          "
          @update:model-value="novo => mudarFreio(campo, novo)"
        />
      </div>
    </div>

    <template #footer>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <Button
          v-if="podeTirar"
          data-tirar
          :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIRAR')"
          icon="i-lucide-trash-2"
          ruby
          link
          class="min-h-11"
          @click="tirar"
        />
        <span v-else />
        <Button
          data-salvar
          :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SALVAR')"
          class="min-h-11"
          :disabled="alvo?.tipo === 'gatilho' && !rascunho"
          @click="salvar"
        />
      </div>
    </template>
  </SidePanel>
</template>
