<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LivreEtapa from '../components/LivreEtapa.vue';
import { LISTAS, P, RITMOS, TETO_MAXIMO } from './passosNovos';
import { contarItens, publicosDaConta } from './adaptadorFalso';

// #2932 — Para cada: a lista em palavras do dia a dia (os cards de uma etapa,
// os contatos com uma etiqueta ou os de um público), o teto por vez e o ritmo.
// Antes de ligar, a tela diz quantos entrariam hoje e mostra os 3 primeiros. Os
// passos de cada um ficam no galho "Em cada um da lista", no Confira.
const props = defineProps({
  modelValue: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  // [{ label: funil, options: [{ value: id, label: etapa }] }]
  etapas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const R = `${P}.REPETIR`;

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const primeiraEtapa = () => props.etapas[0]?.options?.[0]?.value ?? null;
const primeiraEtiqueta = () => props.opcoes.etiquetaPorNome?.[0]?.value || '';
// Os públicos vêm do adaptador falso até o motor existir.
const publicos = computed(() => publicosDaConta(t));
// Começar pronto: a primeira opção de cada lista já vem escolhida.
const NOVA_LISTA = {
  etapa: () => ({ de: 'etapa', etapa_id: primeiraEtapa() }),
  etiqueta: () => ({ de: 'etiqueta', etiqueta: primeiraEtiqueta() }),
  publico: () => ({
    de: 'publico',
    publico_id: publicos.value[0]?.value ?? null,
  }),
};
const listaDe = de => NOVA_LISTA[de]();

const fontes = computed(() =>
  LISTAS.map(de => ({
    value: de,
    label: t(`${R}.DE_${de.toUpperCase()}`),
  }))
);
const ritmos = computed(() =>
  RITMOS.map(ritmo => ({
    value: ritmo,
    label: t(`${R}.RITMO_${ritmo.toUpperCase()}`),
  }))
);

const tetoFora = computed(() => {
  const { teto } = props.modelValue;
  return !Number.isInteger(teto) || teto < 1 || teto > TETO_MAXIMO;
});
const mudarTeto = texto => {
  const numero = Number(texto);
  mudar({ teto: texto === '' || Number.isNaN(numero) ? null : numero });
};

const contagem = computed(() => contarItens(props.modelValue.lista));

// Começar pronto: a primeira etapa já vem escolhida.
onMounted(() => {
  const { lista } = props.modelValue;
  if (lista?.de === 'etapa' && lista.etapa_id == null && primeiraEtapa())
    mudar({ lista: listaDe('etapa') });
});
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="repetir_lista">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.LISTA`) }}
      </span>
      <ChoiceSelect
        data-repetir-de
        :model-value="modelValue.lista?.de || 'etapa'"
        :aria-label="$t(`${R}.LISTA`)"
        :options="fontes"
        @update:model-value="de => mudar({ lista: listaDe(de) })"
      />
    </div>

    <LivreEtapa
      v-if="modelValue.lista?.de === 'etapa'"
      :rotulo="$t(`${R}.QUAL_ETAPA`)"
      :model-value="modelValue.lista.etapa_id"
      :grupos="etapas"
      @update:model-value="
        id => mudar({ lista: { de: 'etapa', etapa_id: id } })
      "
    />
    <div
      v-else-if="modelValue.lista?.de === 'etiqueta'"
      class="flex flex-col gap-1.5"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.QUAL_ETIQUETA`) }}
      </span>
      <ChoiceSelect
        data-repetir-etiqueta
        :model-value="modelValue.lista?.etiqueta || ''"
        :aria-label="$t(`${R}.QUAL_ETIQUETA`)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoes.etiquetaPorNome || []"
        @update:model-value="
          etiqueta => mudar({ lista: { de: 'etiqueta', etiqueta } })
        "
      />
    </div>
    <div v-else class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.QUAL_PUBLICO`) }}
      </span>
      <ChoiceSelect
        data-repetir-publico
        :model-value="modelValue.lista?.publico_id ?? ''"
        :aria-label="$t(`${R}.QUAL_PUBLICO`)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="publicos"
        @update:model-value="
          id => mudar({ lista: { de: 'publico', publico_id: id } })
        "
      />
    </div>

    <div
      data-repetir-contagem
      role="status"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-alpha-2"
    >
      <p class="flex flex-wrap items-baseline m-0 gap-x-2">
        <span class="text-3xl font-bold tabular-nums text-n-teal-11">
          {{ contagem.total }}
        </span>
        <span class="text-[0.9375rem] text-n-slate-12">
          {{ $t(`${R}.ENTRARIAM_HOJE`, {}, contagem.total) }}
        </span>
      </p>
      <ul
        v-if="contagem.primeiros.length"
        class="flex flex-wrap gap-2 p-0 m-0 list-none"
        :aria-label="$t(`${R}.PRIMEIROS`)"
      >
        <li
          v-for="nome in contagem.primeiros"
          :key="nome"
          class="px-3 py-1.5 text-sm rounded-full bg-n-solid-1 text-n-slate-12"
        >
          {{ nome }}
        </li>
      </ul>
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${R}.FICAM_FORA`) }}</p>
    </div>

    <Input
      data-repetir-teto
      type="number"
      :model-value="modelValue.teto ?? ''"
      :label="$t(`${R}.TETO`)"
      :message="
        $t(tetoFora ? `${R}.TETO_FORA` : `${R}.TETO_DICA`, {
          maximo: TETO_MAXIMO,
        })
      "
      :message-type="tetoFora ? 'error' : 'info'"
      @update:model-value="mudarTeto"
    />

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.RITMO`) }}
      </span>
      <ChoiceSelect
        data-repetir-ritmo
        :model-value="modelValue.ritmo || 'aos_poucos'"
        :aria-label="$t(`${R}.RITMO`)"
        :options="ritmos"
        @update:model-value="ritmo => mudar({ ritmo })"
      />
    </div>

    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${R}.ONDE_POR_PASSOS`) }}</p>
  </div>
</template>
