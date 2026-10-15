<script setup>
import { computed } from 'vue';
import { formatoPorChave } from '../../constants';
import Button from 'dashboard/components-next/button/Button.vue';
import { previaCurta } from '../../helpers/conteudo';
import { useRotuloDoCampo } from '../../helpers/campos';
import ModeloConferencia from '../ModeloConferencia.vue';
import ModeloQuemAprova from '../ModeloQuemAprova.vue';
import CustoDoTipo from '../CustoDoTipo.vue';

// Confira: o resumo de cada parte com "Alterar", a conferência do que pode
// causar recusa e quem aprova.
const props = defineProps({
  rascunho: { type: Object, required: true },
  numeros: { type: Array, required: true },
  etapas: { type: Array, required: true },
  rotulos: { type: Object, default: () => ({}) },
  contexto: { type: Object, default: () => ({}) },
  resumoDoFormato: { type: String, default: '' },
});

const emit = defineEmits(['ir']);

const conteudo = computed(() => props.rascunho.conteudo);

// O começo da mensagem, com o nome de cada campo, embaixo do nome do modelo.
const RETICENCIAS = '…';
const rotulo = useRotuloDoCampo();
const comecoDoTexto = computed(() => {
  const { pedacos, cortado } = previaCurta(
    conteudo.value.texto || [],
    rotulo,
    90
  );
  const texto = pedacos
    .map(pedaco => (pedaco.t === 'campo' ? `[${rotulo(pedaco.v)}]` : pedaco.v))
    .join('')
    .trim();
  return cortado ? `${texto}${RETICENCIAS}` : texto;
});

const nomesDosNumeros = computed(() =>
  props.numeros
    .filter(numero => props.rascunho.numeros.includes(numero.id))
    .map(numero => numero.nome)
    .join(', ')
);

const resumo = computed(() =>
  [
    { etapa: 'texto', valor: props.rascunho.nome },
    props.resumoDoFormato
      ? { etapa: 'extras', valor: props.resumoDoFormato }
      : {
          etapa: 'extras',
          chave: 'EXTRAS',
          n: [
            conteudo.value.topo.tipo !== 'nenhum',
            Boolean(conteudo.value.rodape),
            conteudo.value.botoes.length > 0,
          ].filter(Boolean).length,
        },
    { etapa: 'numeros', valor: nomesDosNumeros.value },
  ].filter(item => props.etapas.includes(item.etapa))
);
</script>

<template>
  <div data-etapa-confira class="flex flex-col gap-5">
    <ul
      class="flex flex-col p-0 m-0 list-none rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 divide-y divide-n-weak"
    >
      <li
        v-for="item in resumo"
        :key="item.etapa"
        :data-resumo="item.etapa"
        class="flex items-start justify-between gap-3 px-5 py-4"
      >
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm text-n-slate-10">
            {{
              item.etapa === 'texto'
                ? $t('MODELOS_WHATSAPP.CONFIRA.NOME_E_TEXTO')
                : rotulos[item.etapa] ||
                  $t(`MODELOS_WHATSAPP.ETAPAS.${item.etapa}`)
            }}
          </span>
          <span class="text-base font-medium break-words text-n-slate-12">
            {{
              item.chave
                ? $t('MODELOS_WHATSAPP.CONFIRA.EXTRAS', { n: item.n }, item.n)
                : item.valor || $t('MODELOS_WHATSAPP.CONFIRA.FALTA_PREENCHER')
            }}
          </span>
          <span
            v-if="item.etapa === 'texto' && comecoDoTexto"
            data-resumo-texto
            class="text-sm break-words text-n-slate-11"
          >
            {{ comecoDoTexto }}
          </span>
        </span>
        <Button
          :label="$t('MODELOS_WHATSAPP.ACOES.ALTERAR')"
          icon="i-lucide-pencil"
          color="slate"
          variant="ghost"
          size="sm"
          class="min-h-11 shrink-0"
          @click="emit('ir', item.etapa)"
        />
      </li>
    </ul>
    <ModeloConferencia :conteudo="conteudo" :contexto="contexto" />
    <!-- Quanto custa cada envio do tipo previsto (divulgação diz quanto a mais). -->
    <CustoDoTipo
      v-if="['aviso', 'divulgacao'].includes(rascunho.tipo)"
      :tipo="rascunho.tipo"
    />
    <ModeloQuemAprova
      :tipo="rascunho.tipo"
      :so-divulgacao="Boolean(formatoPorChave(conteudo.formato)?.soDivulgacao)"
      :nao-vai-em-campanha="
        !['padrao', 'produtos'].includes(conteudo.formato || 'padrao')
      "
    />
  </div>
</template>
