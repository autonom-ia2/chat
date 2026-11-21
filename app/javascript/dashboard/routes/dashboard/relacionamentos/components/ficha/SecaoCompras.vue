<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { SEPARADOR } from '../comum/ponto';
import { formatarDiaMes } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { formatarDinheiro, tomDoGrupo } from '../../ficha/compras';
import { textosDasFaixas } from '../../lista/textosDasFaixas';
import { larguraDaBarra } from '../../trazer/larguraDaBarra';
import {
  FAIXAS_PADRAO,
  GRUPOS_DE_COMPRA,
  diasSemComprar,
  grupoPrincipal,
  passouDaHora,
} from '../../fonte/gruposDeCompra';

// #3097 — o que a pessoa já comprou, somado dos cards ganhos nos funis de
// Vender. O foco é o total em letra grande ("R$ 4.820 em 5 compras"); moedas
// diferentes não se somam: a maior vai no número grande e as outras ao lado.
// O selo do canto é o grupo de compra (o mesmo da lista, pelas faixas da conta
// que o servidor manda em `faixas`).
// Com 2 compras ou mais, o bloco do costume: a frase ("Costuma voltar a cada
// 30 dias") e uma barra que mostra onde a pessoa está. A marca é o dia de
// voltar; passou dela, o trecho de atraso fica âmbar e aparece "Chamar de
// volta" (`chamar`), a única ação do cartão. A barra é só desenho
// (aria-hidden): a frase diz o mesmo. Com 1 compra, a data e o que vem com a
// segunda. Quem nunca comprou lê de onde a compra vem. `compras` é null quando
// não há compra. Quem não vê valor de venda recebe as compras sem `por_moeda`:
// o número grande vira quantas compras, sem total nem média. O grupo vem do
// servidor (`grupo`), o mesmo da lista.
const props = defineProps({
  compras: { type: Object, default: null },
  agora: { type: Number, required: true },
  falhou: { type: Boolean, default: false },
  podeChamar: { type: Boolean, default: false },
});
const emit = defineEmits(['chamar', 'tentar']);

const { t } = useI18n();
const idioma = useIdioma();
const rc = (chave, valores, quantos) =>
  quantos === undefined
    ? t(`RELACIONAMENTOS_COMPRAS.FICHA.${chave}`, valores)
    : t(`RELACIONAMENTOS_COMPRAS.FICHA.${chave}`, valores, quantos);

const SEGUNDOS_POR_DIA = 86400;
// Com o trecho de atraso estreito demais, "dia de voltar" encostaria em "hoje".
const ROTULO_DO_MEIO_A_PARTIR_DE = 20;

const comprou = computed(() => Boolean(props.compras?.quantas));
const faixas = computed(() => props.compras?.faixas ?? FAIXAS_PADRAO);
const grupo = computed(() => {
  const id =
    props.compras?.grupo ||
    grupoPrincipal(props.compras, props.agora, faixas.value);
  return GRUPOS_DE_COMPRA.find(item => item.id === id);
});
const textos = computed(() => textosDasFaixas(faixas.value, t));

// A moeda com o maior total vai no número grande.
const moedas = computed(() =>
  [...(props.compras?.por_moeda || [])].sort((a, b) => b.total - a.total)
);
const dinheiro = ({ total, moeda }) =>
  formatarDinheiro(total, moeda, idioma.value);
const principal = computed(() => moedas.value[0]);
const veValores = computed(() => Boolean(principal.value));
const outras = computed(() =>
  moedas.value.slice(1).map(dinheiro).join(SEPARADOR)
);
const media = computed(() => {
  const { total, quantas, moeda } = principal.value;
  return formatarDinheiro(quantas ? total / quantas : 0, moeda, idioma.value);
});

const quantas = computed(() => props.compras?.quantas ?? 0);
const ritmo = computed(() => {
  const dias = props.compras?.intervalo_medio_dias;
  return dias ? Math.round(dias) : null;
});
const dias = computed(() =>
  Math.floor(diasSemComprar(props.compras, props.agora) ?? 0)
);
const atrasado = computed(() => passouDaHora(props.compras, props.agora));
const dataDaUltima = computed(() =>
  formatarDiaMes(props.compras.ultima_em, idioma.value, props.agora)
);
const diaDeVoltar = computed(() =>
  formatarDiaMes(
    props.compras.ultima_em + ritmo.value * SEGUNDOS_POR_DIA,
    idioma.value,
    props.agora
  )
);

// A barra: em dia, a escala é o costume e o verde enche até hoje; atrasado, a
// escala vai até hoje e o costume é a parte verde, com o atraso em âmbar.
const escala = computed(() =>
  atrasado.value ? Math.max(dias.value, 1) : ritmo.value
);
const barra = computed(() => {
  const costume = (ritmo.value / escala.value) * 100;
  return {
    costume: larguraDaBarra(atrasado.value ? costume : 100),
    verde: larguraDaBarra(
      (Math.min(dias.value, ritmo.value) / ritmo.value) * 100
    ),
    rotuloDoMeio: atrasado.value && 100 - costume >= ROTULO_DO_MEIO_A_PARTIR_DE,
  };
});
</script>

<template>
  <CartaoDaSecao :titulo="rc('TITULO')" data-relacionamentos="compras">
    <template v-if="comprou && grupo && !falhou" #acao>
      <SeloDeEstado :tom="tomDoGrupo(grupo.id)" data-relacionamentos="grupo">
        {{ t(grupo.naFicha, textos) }}
      </SeloDeEstado>
    </template>
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <div
      v-else-if="!comprou"
      data-relacionamentos="vazio"
      class="flex items-start gap-3"
    >
      <span
        class="flex items-center justify-center rounded-full size-10 shrink-0 bg-n-alpha-2"
        aria-hidden="true"
      >
        <span class="i-lucide-shopping-bag size-5 text-n-slate-11" />
      </span>
      <div>
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{ rc('NUNCA') }}
        </p>
        <p class="m-0 mt-1 text-sm text-n-slate-11">{{ rc('DE_ONDE') }}</p>
      </div>
    </div>
    <template v-else>
      <p
        v-if="!veValores"
        data-relacionamentos="quantas"
        class="m-0 text-4xl font-bold leading-none tracking-tight tabular-nums text-n-slate-12 md:text-5xl"
      >
        {{ rc('QUANTAS', { count: quantas }, quantas) }}
      </p>
      <p
        v-if="veValores"
        data-relacionamentos="total"
        class="m-0 text-4xl font-bold leading-none tracking-tight tabular-nums text-n-slate-12 md:text-5xl"
      >
        <span class="sr-only">{{ rc('TOTAL_LEITOR') }}</span>
        {{ dinheiro(principal) }}
      </p>
      <p v-if="veValores" class="m-0 mt-2 text-base text-n-slate-11">
        {{ rc('EM_COMPRAS', { count: quantas }, quantas) }}
        <template v-if="quantas > 1">
          {{ SEPARADOR }}{{ rc('MEDIA', { valor: media }) }}
        </template>
        <template v-if="outras">
          {{ SEPARADOR }}{{ rc('OUTRAS_MOEDAS', { valores: outras }) }}
        </template>
      </p>

      <div
        v-if="ritmo"
        data-relacionamentos="ritmo"
        class="flex flex-col gap-4 p-4 mt-5 rounded-2xl md:p-5"
        :class="atrasado ? 'bg-n-amber-2 text-n-amber-12' : 'bg-n-alpha-1'"
      >
        <p class="flex items-start gap-2 m-0 text-base font-semibold">
          <span
            class="mt-0.5 size-5 shrink-0"
            :class="
              atrasado
                ? 'i-lucide-alarm-clock text-n-amber-11'
                : 'i-lucide-repeat text-n-slate-11'
            "
            aria-hidden="true"
          />
          <span>
            {{ rc('RITMO', { count: ritmo }, ritmo) }}
            {{
              atrasado
                ? rc('PASSOU', { count: dias }, dias)
                : rc('EM_DIA', { count: dias }, dias)
            }}
          </span>
        </p>
        <div aria-hidden="true" data-relacionamentos="barra-do-costume">
          <div class="flex h-3 overflow-hidden rounded-full bg-n-alpha-2">
            <span
              class="h-full"
              :class="[
                barra.costume,
                atrasado ? 'border-e-2 border-n-slate-12' : '',
              ]"
            >
              <span class="block h-full bg-n-teal-9" :class="barra.verde" />
            </span>
            <span v-if="atrasado" class="flex-1 h-full bg-n-amber-9" />
          </div>
          <div class="flex mt-1.5 text-xs tabular-nums text-n-slate-11">
            <span
              class="flex justify-between gap-2 shrink-0"
              :class="barra.costume"
            >
              <span>{{ dataDaUltima }}</span>
              <span v-if="!atrasado" class="font-medium">
                {{ rc('VOLTA_EM', { data: diaDeVoltar }) }}
              </span>
              <span v-else-if="barra.rotuloDoMeio">
                {{ rc('DIA_DE_VOLTAR') }}
              </span>
            </span>
            <span v-if="atrasado" class="font-medium ms-auto shrink-0">
              {{ rc('HOJE') }}
            </span>
          </div>
        </div>
        <Button
          v-if="atrasado && podeChamar"
          class="w-full sm:w-auto sm:self-end min-h-11"
          icon="i-lucide-message-circle"
          :label="rc('CHAMAR')"
          @click="emit('chamar')"
        />
      </div>
      <div
        v-else
        data-relacionamentos="uma-compra"
        class="flex items-start gap-3 p-4 mt-5 rounded-2xl bg-n-alpha-1"
      >
        <span
          class="i-lucide-calendar mt-0.5 size-5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <div>
          <p class="m-0 text-base font-medium text-n-slate-12">
            {{ rc('UMA_COMPRA', { data: dataDaUltima }) }}
          </p>
          <p class="m-0 mt-1 text-sm text-n-slate-11">
            {{ rc('UMA_COMPRA_APOIO') }}
          </p>
        </div>
      </div>
    </template>
  </CartaoDaSecao>
</template>
