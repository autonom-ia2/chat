<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — o cabeçalho da lista (v4, T1): "{o quê} · {lugar}" e a linha de
// fatos. Rodada 2: enquanto procura, a frase usa o termo em minúscula
// ("Procurando escritórios em…"); sem empresas, a linha de fatos some (o vazio
// já fala). Rodada 3: a linha conta quem pode ir e quem fica de fora (a mesma
// fonte do botão); depois de tirar alguma, "{vão} vão · {não vão} não vão".
// Enquanto procura, uma frase diz quanto leva.
const props = defineProps({
  busca: { type: Object, default: null },
  carregando: { type: Boolean, default: false },
  leitura: { type: Boolean, default: false },
  achadas: { type: Number, default: 0 },
  vao: { type: Number, default: 0 },
  conferindo: { type: Boolean, default: false },
});
const emit = defineEmits(['mudarPedido']);

const NS = 'PROSPECTING_ACHAR.CONFIRA';
const oQueNaFrase = computed(() => props.busca?.oQue.toLowerCase() || '');
// Rodada 4: um par só, antes e depois de tirar: "{vão} vão · {fora} ficam de
// fora". Enquanto confere, só "{achadas} achadas" (o resto ainda não é final).
const fato = computed(() => {
  const { achadas, vao, conferindo } = props;
  if (conferindo) return { chave: 'FATO_CONFERINDO', valores: { achadas } };
  const fora = achadas - vao;
  if (!fora) return { chave: 'FATO_SEM_FORA', valores: { achadas, vao } };
  return { chave: 'FATO', valores: { achadas, vao, fora } };
});
</script>

<template>
  <header
    v-if="busca"
    class="flex flex-col gap-3 md:flex-row md:items-start"
    data-cabecalho
  >
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
          {{
            leitura
              ? $t(`${NS}.LEITURA.TITULO`)
              : $t(`${NS}.TITULO`, { oQue: busca.oQue, lugar: busca.lugar })
          }}
        </h1>
        <p
          v-if="leitura || achadas"
          class="m-0 text-base text-n-slate-11"
          data-fatos
        >
          <template v-if="leitura">
            {{ $t(`${NS}.TITULO`, { oQue: busca.oQue, lugar: busca.lugar }) }}
          </template>
          <template v-else>
            {{ $t(`${NS}.${fato.chave}`, fato.valores) }}
          </template>
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
