<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import CartaoDaSecao from './CartaoDaSecao.vue';
import { PONTO } from '../comum/ponto';

// #2894 — as 3 últimas conversas: canal, trecho, "há 3 dias" e a situação em
// palavra simples. Na ficha da empresa cada linha diz de quem é (`pessoa`).
const props = defineProps({
  conversas: { type: Array, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['verTodas']);

const QUANTAS_MOSTRAR = 3;
const ICONES = {
  whatsapp: 'i-lucide-message-circle',
  email: 'i-lucide-mail',
  instagram: 'i-lucide-instagram',
  site: 'i-lucide-globe',
};
const TONS = {
  aberta: 'bg-n-teal-3 text-n-teal-11',
  pendente: 'bg-n-amber-3 text-n-amber-11',
  resolvida: 'bg-n-alpha-2 text-n-slate-11',
};

const { t } = useI18n();
const idioma = useIdioma();
const ultimas = computed(() => props.conversas.slice(0, QUANTAS_MOSTRAR));
const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.CONVERSAS.${chave}`, valores);
const trechoDa = conversa =>
  conversa.pessoa
    ? ra('DE', { pessoa: conversa.pessoa, trecho: conversa.trecho })
    : conversa.trecho;
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="conversas">
    <template v-if="conversas.length" #acao>
      <Button slate ghost :label="ra('VER_TODAS')" @click="emit('verTodas')" />
    </template>
    <p
      v-if="!conversas.length"
      data-vazio
      data-relacionamentos="vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-1 p-0 m-0 list-none">
      <li
        v-for="conversa in ultimas"
        :key="conversa.id"
        class="flex items-start min-w-0 gap-3 py-3"
      >
        <span
          class="mt-0.5 size-5 shrink-0 text-n-slate-11"
          :class="ICONES[conversa.canal]"
          :aria-label="ra(`CANAL.${conversa.canal}`)"
          role="img"
        />
        <div class="flex-1 min-w-0">
          <p class="m-0 text-base line-clamp-2 md:truncate text-n-slate-12">
            {{ trechoDa(conversa) }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ quandoRelativo(conversa.quando, agora, idioma) }}
            <span class="md:hidden">
              {{ PONTO }} {{ ra(`SITUACAO.${conversa.situacao}`) }}
            </span>
          </p>
        </div>
        <span
          class="hidden px-2 text-xs font-medium leading-5 rounded-md md:inline-block shrink-0"
          :class="TONS[conversa.situacao]"
        >
          {{ ra(`SITUACAO.${conversa.situacao}`) }}
        </span>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
