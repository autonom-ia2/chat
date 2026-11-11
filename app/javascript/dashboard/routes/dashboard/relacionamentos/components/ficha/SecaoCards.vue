<script setup>
import { useI18n } from 'vue-i18n';
import { formatarReais } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { situacaoDeCardConhecida } from '../../ficha/rotulos';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';

// #2894 — os cards da pessoa: título, funil e etapa, valor e situação. Clicar
// abre a gaveta do card. Na ficha da empresa cada card diz de quem é (`pessoa`).
// O valor vem `null` para quem não pode ver valor: aí não aparece valor nenhum.
// Situação que a tela não conhece ganha o rótulo neutro. `falhou`: a leitura
// não veio.
defineProps({
  cards: { type: Array, required: true },
  falhou: { type: Boolean, default: false },
});
const emit = defineEmits(['abrir', 'tentar']);

const TOM_NEUTRO = 'bg-n-alpha-2 text-n-slate-11';
const TONS = {
  aberto: 'bg-n-blue-3 text-n-blue-11',
  ganho: 'bg-n-teal-3 text-n-teal-11',
  perdido: 'bg-n-ruby-3 text-n-ruby-11',
  resolvido: TOM_NEUTRO,
  cancelado: TOM_NEUTRO,
  outra: TOM_NEUTRO,
};

const { t } = useI18n();
const idioma = useIdioma();
const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.CARDS.${chave}`, valores);
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="cards">
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p
      v-else-if="!cards.length"
      data-vazio
      data-relacionamentos="vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <li v-for="card in cards" :key="card.id">
        <button
          type="button"
          data-relacionamentos="card"
          :aria-label="ra('ABRIR', { titulo: card.titulo })"
          class="flex items-center justify-between w-full gap-3 p-4 text-start transition-colors border rounded-xl border-n-weak hover:border-n-blue-6 hover:bg-n-alpha-1 min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('abrir', card)"
        >
          <span class="min-w-0">
            <span class="block text-base font-medium truncate text-n-slate-12">
              {{ card.titulo }}
            </span>
            <span class="block text-sm text-n-slate-11">
              {{ ra('FUNIL_ETAPA', { funil: card.funil, etapa: card.etapa }) }}
              <template v-if="card.pessoa">
                · {{ ra('DE', { pessoa: card.pessoa }) }}
              </template>
            </span>
          </span>
          <span class="flex flex-col items-end gap-1 shrink-0">
            <span
              v-if="card.valor !== null"
              data-relacionamentos="card-valor"
              class="text-base font-semibold tabular-nums text-n-slate-12"
            >
              {{ formatarReais(card.valor, idioma) }}
            </span>
            <span
              class="px-2 text-xs font-medium leading-5 rounded-md"
              :class="TONS[situacaoDeCardConhecida(card.situacao)]"
            >
              {{ ra(`SITUACAO.${situacaoDeCardConhecida(card.situacao)}`) }}
            </span>
          </span>
        </button>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
