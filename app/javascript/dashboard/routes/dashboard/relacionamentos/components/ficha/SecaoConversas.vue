<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import {
  canalConhecido,
  situacaoDeConversaConhecida,
} from '../../ficha/rotulos';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';
import { PONTO } from '../comum/ponto';

// #2894 — as 3 últimas conversas: canal, trecho, "há 3 dias" e a situação em
// palavra simples. Na ficha da empresa cada linha diz de quem é (`pessoa`).
// Canal ou situação que a tela não conhece ganha o rótulo neutro; conversa sem
// trecho diz que não tem texto. `falhou`: a leitura não veio.
// #2970 — o que ainda não é de verdade não aparece: "Ver todas" daqui só
// avisa, então só existe com `podeVerTodas` (a página liga na demonstração).
// #3071 — com `podeAbrir` (a ficha da pessoa) é de verdade: cada conversa é um
// botão que emite `abrir` com o número dela, e "Ver todas" abre a lista ali
// mesmo (até as 25 mais recentes que o servidor manda), com "Ver menos" para
// fechar. Só aparece quando há mais de 3.
const props = defineProps({
  conversas: { type: Array, required: true },
  agora: { type: Number, default: () => Date.now() },
  falhou: { type: Boolean, default: false },
  podeVerTodas: { type: Boolean, default: false },
  podeAbrir: { type: Boolean, default: false },
});
const emit = defineEmits(['verTodas', 'tentar', 'abrir']);

const QUANTAS_MOSTRAR = 3;
// Relacionamentos::Ficha::Conversas::TETO: o servidor manda no máximo estas.
const TETO_DO_SERVIDOR = 25;
const ICONES = {
  whatsapp: 'i-lucide-message-circle',
  email: 'i-lucide-mail',
  instagram: 'i-lucide-instagram',
  site: 'i-lucide-globe',
  outro: 'i-lucide-messages-square',
};
const TONS = {
  aberta: 'bg-n-teal-3 text-n-teal-11',
  pendente: 'bg-n-amber-3 text-n-amber-11',
  resolvida: 'bg-n-alpha-2 text-n-slate-11',
  adiada: 'bg-n-blue-3 text-n-blue-11',
  outra: 'bg-n-alpha-2 text-n-slate-11',
};

const { t } = useI18n();
const idioma = useIdioma();
const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.CONVERSAS.${chave}`, valores);
const todasAbertas = ref(false);
const temMais = computed(
  () => props.podeAbrir && props.conversas.length > QUANTAS_MOSTRAR
);
const mostrandoTodas = computed(() => temMais.value && todasAbertas.value);
const ultimas = computed(() =>
  (mostrandoTodas.value
    ? props.conversas
    : props.conversas.slice(0, QUANTAS_MOSTRAR)
  ).map(conversa => ({
    ...conversa,
    canal: canalConhecido(conversa.canal),
    situacao: situacaoDeConversaConhecida(conversa.situacao),
  }))
);
const trechoDa = conversa => {
  const trecho = conversa.trecho || ra('SEM_TRECHO');
  return conversa.pessoa
    ? ra('DE', { pessoa: conversa.pessoa, trecho })
    : trecho;
};
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="conversas">
    <template v-if="temMais" #acao>
      <Button
        data-relacionamentos="ver-todas"
        slate
        ghost
        class="!h-11"
        :aria-expanded="mostrandoTodas ? 'true' : 'false'"
        :label="ra(mostrandoTodas ? 'VER_MENOS' : 'VER_TODAS')"
        @click="todasAbertas = !todasAbertas"
      />
    </template>
    <template v-else-if="!podeAbrir && podeVerTodas && conversas.length" #acao>
      <Button slate ghost :label="ra('VER_TODAS')" @click="emit('verTodas')" />
    </template>
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p
      v-else-if="!conversas.length"
      data-vazio
      data-relacionamentos="vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-1 p-0 m-0 list-none">
      <li v-for="conversa in ultimas" :key="conversa.id" class="min-w-0">
        <component
          :is="podeAbrir ? 'button' : 'div'"
          :type="podeAbrir ? 'button' : undefined"
          :data-conversa="podeAbrir ? conversa.id : undefined"
          class="flex items-start w-full min-w-0 gap-3 py-3 bg-transparent border-0 text-start"
          :class="
            podeAbrir &&
            'px-2 -mx-2 rounded-lg cursor-pointer min-h-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand'
          "
          @click="podeAbrir && emit('abrir', conversa.id)"
        >
          <span
            class="mt-0.5 size-5 shrink-0 text-n-slate-11"
            :class="ICONES[conversa.canal]"
            :aria-label="ra(`CANAL.${conversa.canal}`)"
            role="img"
          />
          <span class="flex-1 block min-w-0">
            <span
              class="block m-0 text-base line-clamp-2 md:truncate text-n-slate-12"
            >
              {{ trechoDa(conversa) }}
            </span>
            <span class="block m-0 text-sm text-n-slate-11">
              {{ quandoRelativo(conversa.quando, agora, idioma) }}
              <span class="md:hidden">
                {{ PONTO }} {{ ra(`SITUACAO.${conversa.situacao}`) }}
              </span>
            </span>
          </span>
          <span
            class="hidden px-2 text-xs font-medium leading-5 rounded-md md:inline-block shrink-0"
            :class="TONS[conversa.situacao]"
          >
            {{ ra(`SITUACAO.${conversa.situacao}`) }}
          </span>
        </component>
      </li>
    </ul>
    <p
      v-if="mostrandoTodas && conversas.length >= TETO_DO_SERVIDOR"
      data-relacionamentos="mais-recentes"
      class="m-0 mt-2 text-sm text-n-slate-11"
    >
      {{ ra('MAIS_RECENTES', { count: conversas.length }) }}
    </p>
  </CartaoDaSecao>
</template>
