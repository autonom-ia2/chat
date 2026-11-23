<script setup>
import { computed, ref, useId } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { F, useTextosDaFidelidade } from '../../useTextosDaFidelidade';
import { TOM_DO_CODIGO, codigoDigitado } from '../../regras';

// #3100 — o cliente mostrou um código (no balcão ou na conversa): o atendente
// digita, toca "Conferir" e vê se vale. Valendo, aparece de quem é, o que dá e
// até quando, com "Marcar como usado" (a única ação dali: marca o código como
// gasto, não aplica desconto em lugar nenhum); já usado, vencido ou
// inexistente, a frase diz o que aconteceu. Quem usa pergunta ao servidor
// (`conferir` com o código limpo) e devolve a resposta em `resultado`:
// { estado, oferta, moeda, cliente, vale_ate, usado_em }. Depois de marcado,
// `usado` troca a frase por "Pronto… Dê 10% de desconto ao cliente.".
const props = defineProps({
  resultado: { type: Object, default: null },
  conferindo: { type: Boolean, default: false },
  usando: { type: Boolean, default: false },
  usado: { type: Boolean, default: false },
  agora: { type: Number, required: true },
  codigoInicial: { type: String, default: '' },
});
const emit = defineEmits(['conferir', 'usar']);

const { t, oferta, data } = useTextosDaFidelidade();
const C = `${F}.CONFERIR`;
const idDoCampo = useId();

const codigo = ref(props.codigoInicial);
const conferir = () => {
  const limpo = codigoDigitado(codigo.value);
  if (limpo) emit('conferir', limpo);
};

const TONS = {
  verde: 'bg-n-teal-2 border-n-teal-6 text-n-teal-12',
  neutro: 'bg-n-alpha-1 border-n-weak text-n-slate-12',
  ambar: 'bg-n-amber-2 border-n-amber-6 text-n-amber-12',
  vermelho: 'bg-n-ruby-2 border-n-ruby-6 text-n-ruby-12',
};
const ICONES = {
  valido: 'i-lucide-badge-check',
  usado: 'i-lucide-check-check',
  vencido: 'i-lucide-calendar-x',
  nao_existe: 'i-lucide-search-x',
};
const estado = computed(() => props.resultado?.estado);
const tom = computed(() => TONS[TOM_DO_CODIGO[estado.value]] || TONS.neutro);
const frase = computed(() => {
  const r = props.resultado;
  if (!r) return '';
  if (r.estado === 'valido' && props.usado)
    return t(`${C}.USADO_AGORA`, { oferta: oferta(r.oferta, r.moeda) });
  if (r.estado === 'valido')
    return t(`${C}.RESULTADO.valido`, { oferta: oferta(r.oferta, r.moeda) });
  if (r.estado === 'usado')
    return t(`${C}.RESULTADO.usado`, { data: data(r.usado_em, props.agora) });
  if (r.estado === 'vencido')
    return t(`${C}.RESULTADO.vencido`, { data: data(r.vale_ate, props.agora) });
  return t(`${C}.RESULTADO.nao_existe`);
});
</script>

<template>
  <section
    data-fidelidade="conferir"
    class="flex flex-col gap-4 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
  >
    <div>
      <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
        {{ t(`${C}.TITULO`) }}
      </h2>
      <p class="m-0 mt-1 text-base text-n-slate-11">{{ t(`${C}.APOIO`) }}</p>
    </div>
    <form
      class="flex flex-col gap-3 sm:flex-row sm:items-end"
      @submit.prevent="conferir"
    >
      <div class="flex flex-col flex-1 gap-1">
        <label :for="idDoCampo" class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t(`${C}.CAMPO`) }}
        </label>
        <input
          :id="idDoCampo"
          v-model="codigo"
          data-fidelidade="codigo"
          type="text"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          maxlength="20"
          :placeholder="t(`${C}.EXEMPLO`)"
          class="block w-full h-12 px-4 reset-base !mb-0 border-0 outline-offset-[-1px] placeholder:text-n-slate-10 font-mono text-lg tracking-wider uppercase rounded-xl outline outline-1 outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand bg-n-alpha-black2 text-n-slate-12 placeholder:normal-case placeholder:tracking-normal placeholder:font-sans placeholder:text-base"
        />
      </div>
      <Button
        data-fidelidade="botao-conferir"
        type="submit"
        size="lg"
        class="min-h-12"
        :is-loading="conferindo"
        :disabled="conferindo"
        :label="t(`${C}.BOTAO`)"
      />
    </form>

    <div
      v-if="resultado"
      data-fidelidade="resultado"
      :data-estado="estado"
      role="status"
      class="flex flex-col gap-3 p-4 border rounded-2xl"
      :class="tom"
    >
      <p
        :data-fidelidade="usado ? 'usado-ok' : undefined"
        class="flex items-start gap-2 m-0 text-base font-semibold"
      >
        <span
          :class="usado ? ICONES.usado : ICONES[estado]"
          class="mt-0.5 size-5 shrink-0"
          aria-hidden="true"
        />
        {{ frase }}
      </p>
      <p
        v-if="estado === 'valido' && !usado && resultado.cliente"
        class="m-0 text-sm"
      >
        {{
          t(`${C}.DE_QUEM`, {
            nome: resultado.cliente,
            data: data(resultado.vale_ate, agora),
          })
        }}
      </p>
      <Button
        v-if="estado === 'valido' && !usado"
        data-fidelidade="usar"
        size="lg"
        class="self-start min-h-11"
        icon="i-lucide-ticket-check"
        :is-loading="usando"
        :disabled="usando"
        :label="t(`${C}.USAR`)"
        @click="emit('usar')"
      />
    </div>
  </section>
</template>
