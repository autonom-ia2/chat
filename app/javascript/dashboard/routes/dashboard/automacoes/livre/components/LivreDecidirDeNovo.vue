<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import LivreMarcar from './LivreMarcar.vue';
import LivreDuracao from './LivreDuracao.vue';
import {
  NENHUM,
  marcadosComPassos,
  marcadosDesconhecidos,
  todosMarcados,
} from '../ia';

// #2414 G31 — "a cada resposta, a IA decide": quando a IA escolhe um dos
// caminhos marcados ("ainda conversando"), a automação espera a próxima
// resposta do cliente, até o prazo, e decide de novo. Desligado, o campo sai da
// receita. O caminho marcado não tem passos, e um caminho fica de fora.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  // O passo "decidir" inteiro do rascunho: os caminhos e o galho "nenhum".
  passo: { type: Object, required: true },
  unidades: { type: Array, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const D = 'AUTOMACAO_LIVRE.IA.DE_NOVO';
// O prazo nasce com o do "esperar a resposta" do exemplo 2 (2 horas); quem
// monta a automação troca.
const PRAZO_INICIAL = { valor: 2, unidade: 'horas' };

const ligado = computed(() => Boolean(props.modelValue));
const ligar = valor =>
  emit(
    'update:modelValue',
    valor ? { caminhos: [], prazo: { ...PRAZO_INICIAL } } : null
  );

const opcoes = computed(() => [
  ...(props.passo.caminhos || [])
    .filter(caminho => caminho.chave)
    .map(caminho => ({ value: caminho.chave, label: caminho.nome })),
  { value: NENHUM, label: t('AUTOMACAO_LIVRE.CAMPOS.NENHUM') },
]);

const mudar = (chave, valor) =>
  emit('update:modelValue', { ...props.modelValue, [chave]: valor });

const nomeDoCheio = nome =>
  nome === NENHUM ? t('AUTOMACAO_LIVRE.CAMPOS.NENHUM') : nome;
const avisos = computed(() =>
  ligado.value
    ? [
        ...marcadosDesconhecidos(props.passo).map(chave =>
          t(`${D}.DESCONHECIDO`, { chave })
        ),
        ...marcadosComPassos(props.passo).map(nome =>
          t(`${D}.COM_PASSOS`, { nome: nomeDoCheio(nome) })
        ),
        ...(todosMarcados(props.passo) ? [t(`${D}.TODOS`)] : []),
      ]
    : []
);
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="de_novo">
    <label
      class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
    >
      <span class="text-[0.9375rem] text-n-slate-12">{{ rotulo }}</span>
      <Switch
        class="mx-1.5 scale-[1.4]"
        :model-value="ligado"
        :aria-label="rotulo"
        @update:model-value="ligar"
      />
    </label>
    <template v-if="ligado">
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${D}.DICA`) }}</p>
      <LivreMarcar
        data-de-novo-caminhos
        :rotulo="$t(`${D}.QUANDO`)"
        :opcoes="opcoes"
        :model-value="modelValue.caminhos"
        @update:model-value="valor => mudar('caminhos', valor)"
      />
      <LivreDuracao
        :rotulo="$t(`${D}.PRAZO`)"
        :model-value="modelValue.prazo"
        :unidades="unidades"
        @update:model-value="valor => mudar('prazo', valor)"
      />
      <p
        v-for="aviso in avisos"
        :key="aviso"
        data-aviso-de-novo
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ aviso }}
      </p>
    </template>
  </div>
</template>
