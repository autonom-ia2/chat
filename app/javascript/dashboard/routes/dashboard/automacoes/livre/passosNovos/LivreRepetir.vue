<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LivreEtapa from '../components/LivreEtapa.vue';
import { LISTAS, P, RITMOS, TETO_MAXIMO, listaPronta } from './passosNovos';
import { carregarPublicos, contarLista, publicosDaConta } from './dadosDaConta';

// #2932 — Para cada: a lista em palavras do dia a dia (os cards de uma etapa,
// os contatos com uma etiqueta ou os de um público), o teto por vez e o ritmo.
// Antes de ligar, a tela diz quantos entrariam hoje e mostra os 3 primeiros,
// pela régua do motor (o servidor conta só quem você alcança, sem bloqueados).
// Os passos de cada um ficam no galho "Em cada um da lista", no Confira.
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
// Os públicos salvos da conta (Públicos).
const publicos = computed(() => publicosDaConta());
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

// A contagem de verdade, de novo a cada troca da lista ou do teto. A resposta
// que chega fora de ordem (a pessoa trocou no meio) não vale. O servidor
// pergunta o alcance item a item: quem digita o teto conta uma vez só, quando
// para de digitar.
const contagem = ref({ total: 0, primeiros: [] });
// Passou do teto: o total de verdade e quantos ficam para as próximas vezes,
// numa frase só ("Hoje entram 50 de 120. Os outros 70 entram nas próximas
// vezes."). A leitura que parou no limite diz "mais de".
const paraDepois = computed(() => {
  const {
    total = 0,
    fora_do_teto: fora = 0,
    mais_alem: maisAlem = false,
  } = contagem.value;
  if (!fora) return '';
  const chave = maisAlem ? 'PARA_DEPOIS_MAIS' : 'PARA_DEPOIS';
  return t(`${R}.${chave}`, { total, todos: total + fora, fora });
});
const erroDaContagem = ref('');
let pedido = 0;
const contar = async () => {
  const { lista, teto } = props.modelValue;
  pedido += 1;
  const meu = pedido;
  erroDaContagem.value = '';
  if (!listaPronta(lista) || tetoFora.value) {
    contagem.value = { total: 0, primeiros: [] };
    return;
  }
  try {
    const achou = await contarLista(lista, teto);
    if (meu === pedido) contagem.value = achou;
  } catch (erro) {
    if (meu !== pedido) return;
    contagem.value = { total: 0, primeiros: [] };
    erroDaContagem.value = erro?.response?.data?.error || '';
  }
};
const ESPERA_DA_DIGITACAO = 400;
const contarDepois = useDebounceFn(contar, ESPERA_DA_DIGITACAO);
watch(
  () => [props.modelValue.lista, props.modelValue.teto],
  () => contarDepois(),
  { deep: true }
);

// Começar pronto: a primeira etapa já vem escolhida.
onMounted(() => {
  carregarPublicos();
  const { lista } = props.modelValue;
  if (lista?.de === 'etapa' && lista.etapa_id == null && primeiraEtapa())
    mudar({ lista: listaDe('etapa') });
  else contar();
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
          {{ $t(`${R}.ENTRAM_HOJE`, {}, contagem.total) }}
        </span>
      </p>
      <p
        v-if="paraDepois"
        data-repetir-para-depois
        class="mb-0 text-[0.9375rem] font-medium text-n-slate-12"
      >
        {{ paraDepois }}
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
      <p
        v-if="erroDaContagem"
        data-repetir-erro
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ erroDaContagem }}
      </p>
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
