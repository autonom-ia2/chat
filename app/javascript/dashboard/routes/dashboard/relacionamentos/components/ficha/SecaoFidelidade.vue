<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';
import DialogoDaFicha from './DialogoDaFicha.vue';
import FalhaDaParte from './FalhaDaParte.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import CartaoDeCarimbos from 'dashboard/routes/dashboard/fidelidade/components/CartaoDeCarimbos.vue';
import {
  F,
  useTextosDaFidelidade,
} from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';
import {
  pertoDoPremio,
  progresso,
} from 'dashboard/routes/dashboard/fidelidade/regras';
import {
  fraseDoMovimento,
  sinalDoMovimento,
} from 'dashboard/routes/dashboard/fidelidade/historico';

// #3100 — o cartão fidelidade da pessoa, na ficha (logo depois de Compras).
// O cartão compacto mostra quantos ela tem e quanto falta; completou, a faixa
// verde diz que pode dar o prêmio (e quantos ficam para o próximo cartão) e
// "Dar o prêmio" é a ação do bloco (só para quem pode mexer no contato,
// `podeDarPremio`; quem usa confirma no DialogoDarPremio). Embaixo: o que vence
// logo, os últimos movimentos (com "Ver tudo" quando há mais) e os cupons da
// pessoa, com "Marcar como usado" no que ainda vale, que pergunta antes de
// gastar o cupom. Sem nada ainda, a frase diz como ela ganha o primeiro. O bloco só
// aparece com o programa criado; pausado, avisa que os carimbos ficam
// guardados (e, com data de vencer à vista, que vencem nela mesmo assim). `saldo`: { tem, vencem, historico, historico_total, cupons }.
// O código de cada cupom só chega para quem pode usá-lo ou vê o painel
// Fidelidade; sem ele, o cupom aparece só com o estado e a oferta.
const props = defineProps({
  programa: { type: Object, required: true },
  saldo: { type: Object, default: null },
  agora: { type: Number, required: true },
  falhou: { type: Boolean, default: false },
  podeDarPremio: { type: Boolean, default: false },
  podeUsarCupom: { type: Boolean, default: false },
});
const emit = defineEmits(['darPremio', 'usarCupom', 'verTudo', 'tentar']);

const { t, unidade, nomeDaUnidade, dinheiro, data, oferta, premioNaFrase } =
  useTextosDaFidelidade();
const FI = `${F}.FICHA`;

const tem = computed(() => props.saldo?.tem ?? 0);
const conta = computed(() => progresso(tem.value, props.programa.meta));
const perto = computed(() => pertoDoPremio(tem.value, props.programa.meta));
const historico = computed(() => props.saldo?.historico || []);
const cupons = computed(() => props.saldo?.cupons || []);
const nada = computed(
  () => !tem.value && !historico.value.length && !cupons.value.length
);
const maisHistorico = computed(
  () => (props.saldo?.historico_total ?? 0) > historico.value.length
);
const vencem = computed(() => props.saldo?.vencem || null);

// Um toque errado não pode gastar o cupom: pergunta antes.
const dialogoCupom = ref(null);
const cupomEscolhido = ref(null);
const perguntarCupom = cupom => {
  cupomEscolhido.value = cupom;
  dialogoCupom.value?.open();
};
const usarCupom = () => {
  dialogoCupom.value?.close();
  emit('usarCupom', cupomEscolhido.value);
};

const linha = movimento => {
  const { chave, valores } = fraseDoMovimento(movimento, {
    unidade,
    dinheiro,
    tipo: props.programa.tipo,
  });
  return t(`${FI}.MOV.${chave}`, valores);
};
const estadoDoCupom = cupom => {
  if (cupom.estado === 'usado')
    return t(`${FI}.CUPOM_USADO`, { data: data(cupom.usado_em, props.agora) });
  if (cupom.estado === 'vencido')
    return t(`${FI}.CUPOM_VENCIDO`, {
      data: data(cupom.vale_ate, props.agora),
    });
  return t(`${FI}.CUPOM_VALE`, {
    oferta: oferta(cupom.oferta, cupom.moeda),
    data: data(cupom.vale_ate, props.agora),
  });
};
</script>

<template>
  <CartaoDaSecao :titulo="t(`${FI}.TITULO`)" data-relacionamentos="fidelidade">
    <template v-if="!falhou && perto" #acao>
      <SeloDeEstado tom="verde">{{ t(`${FI}.SELO_PERTO`) }}</SeloDeEstado>
    </template>

    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <div v-else class="flex flex-col gap-4">
      <p
        v-if="!programa.ligado"
        data-fidelidade="ficha-pausado"
        class="px-4 py-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-12"
      >
        {{
          t(vencem ? `${FI}.PAUSADO_VENCEM` : `${FI}.PAUSADO`, {
            unidade: nomeDaUnidade(programa.tipo),
          })
        }}
      </p>

      <div
        v-if="nada"
        data-fidelidade="ficha-vazia"
        class="flex items-start gap-3"
      >
        <span
          class="flex items-center justify-center rounded-full size-10 shrink-0 bg-n-alpha-2"
          aria-hidden="true"
        >
          <span class="i-lucide-gift size-5 text-n-slate-11" />
        </span>
        <div>
          <p class="m-0 text-base font-medium text-n-slate-12">
            {{
              t(`${FI}.SEM_SALDO`, { unidade: nomeDaUnidade(programa.tipo) })
            }}
          </p>
          <p class="m-0 mt-1 text-sm text-n-slate-11">
            {{
              t(`${FI}.SEM_SALDO_APOIO`, {
                valor: dinheiro(programa.a_cada, programa.moeda),
              })
            }}
          </p>
          <p class="m-0 mt-1 text-sm text-n-slate-11">
            {{
              t(`${FI}.SEM_SALDO_PREMIO`, {
                premio: premioNaFrase(programa.premio),
              })
            }}
          </p>
        </div>
      </div>

      <template v-else>
        <CartaoDeCarimbos
          compacto
          :tipo="programa.tipo"
          :meta="programa.meta"
          :tem="tem"
          :premio="programa.premio"
        />

        <div
          v-if="conta.completo"
          data-fidelidade="completo"
          class="flex flex-col gap-3 p-4 rounded-2xl bg-n-teal-2 text-n-teal-12 sm:flex-row sm:items-center sm:justify-between"
        >
          <p class="flex items-start gap-2 m-0 text-base font-semibold">
            <span
              class="i-lucide-party-popper mt-0.5 size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            <span class="flex flex-col gap-0.5">
              <span>
                {{ t(`${FI}.COMPLETO`) }}
                <template v-if="conta.premios > 1">
                  {{
                    t(
                      `${FI}.PREMIOS_JUNTOS`,
                      { count: conta.premios },
                      conta.premios
                    )
                  }}
                </template>
              </span>
              <span
                v-if="conta.sobra"
                data-fidelidade="sobra"
                class="text-sm font-normal"
              >
                {{
                  t(`${F}.DAR_PREMIO.SOBRA`, {
                    quantos: unidade(conta.sobra, programa.tipo),
                  })
                }}
              </span>
            </span>
          </p>
          <Button
            v-if="podeDarPremio"
            data-fidelidade="dar-premio"
            icon="i-lucide-gift"
            class="w-full sm:w-auto min-h-11 shrink-0"
            :label="t(`${FI}.DAR_PREMIO`)"
            @click="emit('darPremio')"
          />
        </div>

        <p
          v-if="vencem"
          data-fidelidade="vencem"
          class="flex items-center gap-2 m-0 text-sm text-n-amber-11"
        >
          <span class="i-lucide-hourglass size-4 shrink-0" aria-hidden="true" />
          {{
            t(`${FI}.VENCEM`, {
              quantos: unidade(vencem.quantos, programa.tipo),
              data: data(vencem.em, agora),
            })
          }}
        </p>
      </template>

      <div v-if="historico.length" data-fidelidade="historico">
        <h3 class="m-0 mb-2 text-sm font-semibold text-n-slate-11">
          {{ t(`${FI}.HISTORICO`) }}
        </h3>
        <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
          <li
            v-for="movimento in historico"
            :key="movimento.id"
            :data-movimento="movimento.tipo"
            class="flex items-center gap-3 py-2.5"
          >
            <span
              class="inline-flex justify-center px-1.5 text-sm font-semibold rounded-md min-w-10 tabular-nums"
              :class="
                movimento.quantos > 0
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ sinalDoMovimento(movimento.quantos) }}
            </span>
            <span class="flex-1 min-w-0 text-sm text-n-slate-12">
              {{ linha(movimento) }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11 shrink-0">
              {{ data(movimento.em, agora) }}
            </span>
          </li>
        </ul>
        <Button
          v-if="maisHistorico"
          variant="link"
          class="mt-1 min-h-11"
          :label="t(`${FI}.VER_TUDO`)"
          @click="emit('verTudo')"
        />
      </div>

      <div v-if="cupons.length" data-fidelidade="cupons-da-pessoa">
        <h3 class="m-0 mb-2 text-sm font-semibold text-n-slate-11">
          {{ t(`${FI}.CUPONS`) }}
        </h3>
        <ul class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="cupom in cupons"
            :key="cupom.id"
            :data-cupom="cupom.estado"
            class="flex flex-col gap-3 p-3 rounded-xl bg-n-alpha-1 sm:flex-row sm:items-center"
          >
            <code
              v-if="cupom.codigo"
              data-fidelidade="codigo-do-cupom"
              class="self-start px-2 py-1 font-mono text-sm font-semibold tracking-wider border border-dashed rounded-md sm:self-center border-n-slate-7 text-n-slate-12"
              :class="
                cupom.estado === 'valido' ? '' : 'line-through opacity-60'
              "
            >
              {{ cupom.codigo }}
            </code>
            <span class="flex-1 min-w-0 text-sm text-n-slate-11">
              {{ estadoDoCupom(cupom) }}
            </span>
            <Button
              v-if="cupom.estado === 'valido' && podeUsarCupom"
              data-fidelidade="usar-cupom"
              variant="faded"
              size="sm"
              class="min-h-11 shrink-0"
              :label="t(`${FI}.USAR_CUPOM`)"
              @click="perguntarCupom(cupom)"
            />
          </li>
        </ul>
      </div>
    </div>

    <DialogoDaFicha
      v-if="podeUsarCupom"
      ref="dialogoCupom"
      :titulo="
        t(`${FI}.USAR_CUPOM_TITULO`, { codigo: cupomEscolhido?.codigo || '' })
      "
      :texto="t(`${FI}.USAR_CUPOM_TEXTO`)"
      :confirmar="t(`${FI}.USAR_CUPOM_CONFIRMAR`)"
      :cancelar="t(`${FI}.CANCELAR`)"
      marca-confirmar="confirmar-usar-cupom"
      margem-no-celular
      @confirm="usarCupom"
    />
  </CartaoDaSecao>
</template>
