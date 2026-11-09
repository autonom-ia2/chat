<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import {
  chaveDoModelo,
  corpoDoModelo,
  variaveisDoCorpo,
} from '../modeloWhatsapp';
import {
  PARA_TODOS,
  caixasDaCampanha,
  comFaz,
  comPublico,
  ehPropaganda,
  modelosDaCaixa,
  paraTodos,
} from '../campanha';

// #2414 G14 (#2630) — o passo "campanha" inteiro: o que fazer e, para mandar,
// a caixa do WhatsApp oficial, o modelo aprovado com o texto fixo de cada
// variável, o nome e quem recebe (as etiquetas ou todos os contatos, menos quem
// tem as etiquetas excluídas). O servidor confere tudo de novo ao salvar,
// inclusive que o gatilho roda sozinho.
const props = defineProps({
  modelValue: { type: Object, required: true },
  etiquetas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const C = 'AUTOMACAO_LIVRE.CAMPANHA';
const idFaz = useId();
const idCaixa = useId();
const idModelo = useId();
const idPublico = useId();

const passo = computed(() => props.modelValue);
const disparar = computed(() => passo.value.faz === 'disparar');
const mudar = mudanca =>
  emit('update:modelValue', { ...passo.value, ...mudanca });

const opcoesDoFaz = computed(() => [
  { value: 'nao_receber', label: t(`${C}.NAO_RECEBER`) },
  { value: 'disparar', label: t(`${C}.DISPARAR`) },
]);
const escolherFaz = faz => emit('update:modelValue', comFaz(passo.value, faz));

const todos = computed(() => paraTodos(passo.value));
const opcoesDoPublico = computed(() => [
  { value: 'etiquetas', label: t(`${C}.PUBLICO_ETIQUETAS`) },
  { value: PARA_TODOS, label: t(`${C}.PUBLICO_TODOS`) },
]);
const escolherPublico = publico =>
  emit('update:modelValue', comPublico(passo.value, publico));

const todasAsCaixas = useMapGetter('inboxes/getInboxes');
const caixas = computed(() => caixasDaCampanha(todasAsCaixas.value));
const opcoesDaCaixa = computed(() =>
  caixas.value.map(caixa => ({ value: caixa.id, label: caixa.name }))
);
const caixa = computed(() =>
  caixas.value.find(item => item.id === passo.value.caixa_id)
);
const escolherCaixa = id => mudar({ caixa_id: id, modelo: undefined });

const modelos = computed(() => modelosDaCaixa(caixa.value));
const opcoesDoModelo = computed(() =>
  modelos.value.map(modelo => ({
    value: chaveDoModelo(modelo),
    label: t(`${C}.MODELO_OPCAO`, {
      nome: modelo.name,
      idioma: modelo.language,
    }),
  }))
);
const escolhido = computed(() =>
  modelos.value.find(
    modelo => chaveDoModelo(modelo) === chaveDoModelo(passo.value.modelo)
  )
);
const corpo = computed(() => corpoDoModelo(escolhido.value));
const variaveis = computed(() =>
  [...variaveisDoCorpo(corpo.value)].sort((a, b) => Number(a) - Number(b))
);
const escolherModelo = chave => {
  const modelo = modelos.value.find(item => chaveDoModelo(item) === chave);
  if (!modelo) return;
  const quantas = variaveisDoCorpo(corpoDoModelo(modelo)).length;
  mudar({
    modelo: {
      nome: modelo.name,
      idioma: modelo.language,
      variaveis: Array.from({ length: quantas }, () => []),
    },
  });
};
// Texto fixo: a campanha vai para muita gente de uma vez (sem dado do contato).
const textoDa = indice =>
  passo.value.modelo?.variaveis?.[indice]?.join('') || '';
const mudarVariavel = (indice, texto) => {
  const novas = variaveis.value.map((_, posicao) =>
    posicao === indice
      ? [texto]
      : passo.value.modelo?.variaveis?.[posicao] || []
  );
  mudar({ modelo: { ...passo.value.modelo, variaveis: novas } });
};
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="campanha">
    <div class="flex flex-col gap-1.5">
      <label :for="idFaz" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.CAMPOS.FAZ') }}
      </label>
      <ChoiceSelect
        data-campanha-faz
        :model-value="passo.faz"
        :trigger-id="idFaz"
        :aria-label="$t('AUTOMACAO_LIVRE.CAMPOS.FAZ')"
        :options="opcoesDoFaz"
        @update:model-value="escolherFaz"
      />
    </div>

    <p v-if="!disparar" class="mb-0 text-sm text-n-slate-11">
      {{ $t(`${C}.NAO_RECEBER_DICA`) }}
    </p>

    <template v-else>
      <p
        data-campanha-so-recorrente
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${C}.SO_RECORRENTE`) }}
      </p>

      <Input
        data-campanha-titulo
        :model-value="passo.titulo || ''"
        :label="$t('AUTOMACAO_LIVRE.CAMPOS.TITULO')"
        :max-length="255"
        @update:model-value="titulo => mudar({ titulo })"
      />

      <div class="flex flex-col gap-1.5">
        <label :for="idCaixa" class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.CAMPOS.CAIXA_ID') }}
        </label>
        <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.CAIXA_DICA`) }}</p>
        <ChoiceSelect
          data-campanha-caixa
          :model-value="passo.caixa_id ?? ''"
          :trigger-id="idCaixa"
          :aria-label="$t('AUTOMACAO_LIVRE.CAMPOS.CAIXA_ID')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDaCaixa"
          @update:model-value="escolherCaixa"
        />
        <p v-if="!caixas.length" class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.SEM_CAIXA`) }}
        </p>
      </div>

      <div v-if="caixa" class="flex flex-col gap-1.5">
        <label :for="idModelo" class="text-sm font-medium text-n-slate-12">
          {{ $t(`${C}.MODELO`) }}
        </label>
        <ChoiceSelect
          data-campanha-modelo
          :model-value="escolhido ? chaveDoModelo(escolhido) : ''"
          :trigger-id="idModelo"
          :aria-label="$t(`${C}.MODELO`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDoModelo"
          @update:model-value="escolherModelo"
        />
        <p v-if="!modelos.length" class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.SEM_MODELO`) }}
        </p>
        <p
          v-else-if="passo.modelo && !escolhido"
          data-campanha-modelo-sumiu
          role="status"
          class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
        >
          {{ $t(`${C}.MODELO_SUMIU`, { nome: passo.modelo.nome }) }}
        </p>
      </div>

      <template v-if="escolhido">
        <p
          v-if="ehPropaganda(escolhido)"
          data-campanha-custo
          class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          {{ $t(`${C}.CUSTO_PROPAGANDA`) }}
        </p>
        <p
          class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-12 whitespace-pre-line"
        >
          {{ corpo }}
        </p>
        <p v-if="variaveis.length" class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.VARIAVEL_DICA`) }}
        </p>
        <Input
          v-for="(variavel, indice) in variaveis"
          :key="variavel"
          data-campanha-variavel
          :model-value="textoDa(indice)"
          :label="$t(`${C}.VARIAVEL`, { numero: variavel })"
          @update:model-value="texto => mudarVariavel(indice, texto)"
        />
      </template>

      <div class="flex flex-col gap-1.5">
        <label :for="idPublico" class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.CAMPOS.PUBLICO') }}
        </label>
        <ChoiceSelect
          data-campanha-publico
          :model-value="todos ? PARA_TODOS : 'etiquetas'"
          :trigger-id="idPublico"
          :aria-label="$t('AUTOMACAO_LIVRE.CAMPOS.PUBLICO')"
          :options="opcoesDoPublico"
          @update:model-value="escolherPublico"
        />
        <p v-if="todos" class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.PUBLICO_TODOS_DICA`) }}
        </p>
      </div>

      <div v-if="!todos" class="flex flex-col gap-1.5">
        <LivreMarcar
          :rotulo="$t('AUTOMACAO_LIVRE.CAMPOS.ETIQUETAS')"
          :opcoes="etiquetas"
          :model-value="passo.etiquetas || []"
          @update:model-value="novas => mudar({ etiquetas: novas })"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            etiquetas.length
              ? $t(`${C}.ETIQUETAS_DICA`)
              : $t(`${C}.SEM_ETIQUETAS`)
          }}
        </p>
      </div>

      <div
        v-if="etiquetas.length"
        class="flex flex-col gap-1.5"
        data-campanha-sem
      >
        <LivreMarcar
          :rotulo="$t('AUTOMACAO_LIVRE.CAMPOS.SEM_ETIQUETAS')"
          :opcoes="etiquetas"
          :model-value="passo.sem_etiquetas || []"
          @update:model-value="novas => mudar({ sem_etiquetas: novas })"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.SEM_ETIQUETAS_DICA`) }}
        </p>
      </div>
    </template>
  </div>
</template>
