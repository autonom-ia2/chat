<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — o cabeçalho da lista (v4, T1): "{o quê} · {lugar}" e a linha de
// fatos. Rodada 2: enquanto procura, a frase usa o termo em minúscula
// ("Procurando escritórios em…"); sem empresas, a linha de fatos some (o vazio
// já fala). Enquanto procura, uma frase diz quanto leva.
// P3 (crítica r5): contas separadas, que fecham nas achadas — "20 achadas ·
// 13 vão · 2 você tirou · 4 ficam de fora · 1 você já mandou". Conta zerada
// não aparece. Enquanto confere, e para quem só lê, só "{achadas} achadas"
// (D10: quem só lê vê o mesmo título da busca).
const props = defineProps({
  // A página só mostra o cabeçalho com a busca conhecida (v-if lá).
  busca: { type: Object, required: true },
  carregando: { type: Boolean, default: false },
  leitura: { type: Boolean, default: false },
  contas: {
    type: Object,
    default: () => ({ achadas: 0, vao: 0, tiradas: 0, fora: 0, mandadas: 0 }),
  },
  conferindo: { type: Boolean, default: false },
});
const emit = defineEmits(['mudarPedido']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.CONFIRA';
const oQueNaFrase = computed(() => props.busca.oQue.toLowerCase());
const ORDEM = [
  ['achadas', 'ACHADAS'],
  ['vao', 'VAO'],
  ['tiradas', 'TIROU'],
  ['fora', 'FORA'],
  ['mandadas', 'MANDOU'],
];
const fatos = computed(() => {
  const fato = ([campo, chave]) =>
    t(`${NS}.FATOS.${chave}`, { n: props.contas[campo] }, props.contas[campo]);
  if (props.conferindo || props.leitura) return fato(ORDEM[0]);
  return ORDEM.filter(([campo]) => campo === 'achadas' || props.contas[campo])
    .map(fato)
    .join(t('PROSPECTING_ACHAR.COMUM.SEPARADOR'));
});
const achadas = computed(() => props.contas.achadas);
</script>

<template>
  <header class="flex flex-col gap-3 md:flex-row md:items-start" data-cabecalho>
    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <h1
        v-if="carregando"
        class="m-0 text-2xl font-bold tracking-tight break-words md:text-[2rem] md:leading-tight text-n-slate-12"
        data-buscando
      >
        {{ $t(`${NS}.BUSCANDO`, { oQue: oQueNaFrase, lugar: busca.lugar }) }}
      </h1>
      <template v-if="carregando">
        <p class="m-0 text-base text-n-slate-11">
          {{ $t(`${NS}.BUSCANDO_DICA`) }}
        </p>
        <div
          class="h-1.5 mt-2 overflow-hidden rounded-full bg-n-blue-4"
          role="progressbar"
          :aria-label="$t(`${NS}.BUSCANDO_DICA`)"
        >
          <div class="w-1/3 h-full rounded-full bg-n-blue-9 animate-pulse" />
        </div>
      </template>
      <template v-else>
        <h1
          class="m-0 text-2xl font-bold tracking-tight break-words md:text-[2rem] md:leading-tight text-n-slate-12"
        >
          {{ $t(`${NS}.TITULO`, { oQue: busca.oQue, lugar: busca.lugar }) }}
        </h1>
        <p v-if="achadas" class="m-0 text-base text-n-slate-11" data-fatos>
          {{ fatos }}
        </p>
      </template>
    </div>
    <Button
      v-if="!leitura && !carregando && achadas"
      :label="$t(`${NS}.MUDAR_PEDIDO`)"
      icon="i-lucide-pencil"
      slate
      faded
      class="self-start !min-h-11 !rounded-xl shrink-0"
      data-mudar-pedido
      @click="emit('mudarPedido')"
    />
  </header>
</template>
