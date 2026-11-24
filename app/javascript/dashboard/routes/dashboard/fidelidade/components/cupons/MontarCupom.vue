<script setup>
import { computed, nextTick, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import EscolhaEmCartoes from '../EscolhaEmCartoes.vue';
import { F, useTextosDaFidelidade } from '../../useTextosDaFidelidade';
import {
  OFERTAS,
  PREFIXO_MAXIMO,
  VALIDADES_DO_CUPOM,
  errosDoCupom,
  exemploDeCodigo,
  prefixoLimpo,
} from '../../regras';

// #3100 — criar um cupom: o nome (só a conta vê), o que ele dá (desconto em %,
// desconto em dinheiro ou um presente), o começo do código e quanto tempo vale
// depois que o cliente recebe. Cada cliente recebe um código só dele e usa uma
// vez (regra fixa nesta fase). À direita (no celular, depois do formulário), a
// mensagem como chega no WhatsApp (o mesmo texto que o passo "Mandar cupom" já
// traz escrito). O botão
// principal nunca fica apagado: com algo faltando, o campo diz o quê, a faixa
// vermelha acima dos botões avisa e o foco vai ao primeiro campo errado.
const props = defineProps({
  modelValue: { type: Object, required: true },
  salvando: { type: Boolean, default: false },
  agora: { type: Number, required: true },
});
const emit = defineEmits(['update:modelValue', 'salvar', 'cancelar']);

const { t, oferta, data } = useTextosDaFidelidade();
const M = `${F}.MONTAR_CUPOM`;
const SEGUNDOS_POR_DIA = 86400;

const cupom = computed(() => props.modelValue);
const mudar = mudanca =>
  emit('update:modelValue', { ...cupom.value, ...mudanca });
const mudarOferta = mudanca =>
  mudar({ oferta: { ...cupom.value.oferta, ...mudanca } });

const tentou = ref(false);
const erros = computed(() => (tentou.value ? errosDoCupom(cupom.value) : []));
const tipoDe = campo => (erros.value.includes(campo) ? 'error' : 'info');
const invalido = campo => erros.value.includes(campo) || undefined;
const msg = (campo, dica = '') =>
  erros.value.includes(campo) ? t(`${M}.ERROS.${campo}`) : dica;
const formulario = ref(null);
const salvar = async () => {
  tentou.value = true;
  if (!errosDoCupom(cupom.value).length) {
    emit('salvar');
    return;
  }
  await nextTick();
  formulario.value
    ?.querySelector(':is(input, button)[aria-invalid="true"]')
    ?.focus();
};

const ofertas = computed(() => [
  {
    value: OFERTAS.PORCENTAGEM,
    titulo: t(`${M}.OFERTA_PORCENTAGEM`),
    icone: 'i-lucide-percent',
  },
  {
    value: OFERTAS.VALOR,
    titulo: t(`${M}.OFERTA_VALOR`),
    icone: 'i-lucide-banknote',
  },
  {
    value: OFERTAS.PRESENTE,
    titulo: t(`${M}.OFERTA_PRESENTE`),
    icone: 'i-lucide-gift',
  },
]);
const validades = computed(() =>
  VALIDADES_DO_CUPOM.map(dias => ({
    value: dias,
    label: t(`${M}.VALIDADES`, { count: dias }, dias),
  }))
);
const numero = valor => (valor === '' ? null : valor);

const codigo = computed(() => exemploDeCodigo(cupom.value.prefixo));
const previa = computed(() =>
  t(`${M}.PREVIA_TEXTO`, {
    codigo: codigo.value,
    oferta: oferta(cupom.value.oferta, cupom.value.moeda) || '…',
    data: data(
      props.agora / 1000 + (cupom.value.validade_dias || 0) * SEGUNDOS_POR_DIA,
      props.agora
    ),
  })
);
</script>

<template>
  <div data-fidelidade="montar-cupom" class="flex flex-col gap-6">
    <header class="flex flex-col gap-2">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12 md:text-3xl"
      >
        {{ t(`${M}.TITULO`) }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">{{ t(`${M}.APOIO`) }}</p>
    </header>

    <div class="flex flex-col gap-6 lg:grid lg:grid-cols-5 lg:items-start">
      <aside
        class="flex flex-col order-2 gap-3 lg:col-span-2 lg:sticky lg:top-6"
      >
        <p class="m-0 text-sm font-medium text-n-slate-11">
          {{ t(`${M}.PREVIA`) }}
        </p>
        <figure
          data-fidelidade="previa-cupom"
          class="flex flex-col gap-3 p-4 m-0 rounded-3xl bg-n-alpha-2"
        >
          <div
            class="flex flex-col self-start w-full max-w-sm gap-3 p-3 shadow-sm rounded-2xl rounded-ss-sm bg-n-teal-3"
          >
            <p class="m-0 text-[0.9375rem] text-n-slate-12 whitespace-pre-line">
              {{ previa }}
            </p>
            <p
              class="flex items-center justify-center gap-2 py-3 m-0 font-mono text-xl font-bold tracking-widest border-2 border-dashed rounded-xl border-n-teal-8 bg-n-solid-1 text-n-slate-12"
            >
              <span
                class="i-lucide-ticket size-5 text-n-teal-11"
                aria-hidden="true"
              />
              {{ codigo }}
            </p>
          </div>
          <figcaption class="text-xs text-n-slate-11">
            {{ t(`${M}.PREVIA_DICA`) }}
          </figcaption>
        </figure>
      </aside>

      <section
        ref="formulario"
        class="flex flex-col gap-6 p-5 border shadow-sm lg:order-1 lg:col-span-3 rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
      >
        <Input
          data-fidelidade="nome-do-cupom"
          :model-value="cupom.nome || ''"
          :label="t(`${M}.NOME`)"
          :placeholder="t(`${M}.NOME_EXEMPLO`)"
          maxlength="60"
          :message="msg('NOME', t(`${M}.NOME_DICA`))"
          :message-type="tipoDe('NOME')"
          :aria-invalid="invalido('NOME')"
          wrap-message
          @update:model-value="nome => mudar({ nome })"
        />

        <EscolhaEmCartoes
          :model-value="cupom.oferta.tipo"
          :legenda="t(`${M}.OFERTA`)"
          :opcoes="ofertas"
          @update:model-value="tipo => mudarOferta({ tipo })"
        />
        <Input
          v-if="cupom.oferta.tipo === OFERTAS.PORCENTAGEM"
          data-fidelidade="oferta-valor"
          type="number"
          min="1"
          max="100"
          inputmode="numeric"
          :model-value="cupom.oferta.valor ?? ''"
          :label="t(`${M}.PORCENTAGEM`)"
          :message="msg('OFERTA')"
          :message-type="tipoDe('OFERTA')"
          :aria-invalid="invalido('OFERTA')"
          wrap-message
          @update:model-value="valor => mudarOferta({ valor: numero(valor) })"
        />
        <Input
          v-else-if="cupom.oferta.tipo === OFERTAS.VALOR"
          data-fidelidade="oferta-valor"
          type="number"
          min="1"
          inputmode="numeric"
          :model-value="cupom.oferta.valor ?? ''"
          :label="t(`${M}.VALOR`)"
          :message="msg('OFERTA')"
          :message-type="tipoDe('OFERTA')"
          :aria-invalid="invalido('OFERTA')"
          wrap-message
          @update:model-value="valor => mudarOferta({ valor: numero(valor) })"
        />
        <Input
          v-else
          data-fidelidade="oferta-texto"
          :model-value="cupom.oferta.texto || ''"
          :label="t(`${M}.PRESENTE`)"
          :placeholder="t(`${M}.PRESENTE_EXEMPLO`)"
          maxlength="60"
          :message="msg('OFERTA')"
          :message-type="tipoDe('OFERTA')"
          :aria-invalid="invalido('OFERTA')"
          wrap-message
          @update:model-value="texto => mudarOferta({ texto })"
        />

        <div class="grid gap-4 sm:grid-cols-2">
          <Input
            data-fidelidade="prefixo"
            :model-value="cupom.prefixo || ''"
            :label="t(`${M}.PREFIXO`)"
            :placeholder="t(`${M}.PREFIXO_EXEMPLO`)"
            :maxlength="PREFIXO_MAXIMO"
            :message="msg('PREFIXO', t(`${M}.PREFIXO_DICA`, { codigo }))"
            :message-type="tipoDe('PREFIXO')"
            :aria-invalid="invalido('PREFIXO')"
            wrap-message
            @update:model-value="
              texto => mudar({ prefixo: prefixoLimpo(texto) })
            "
          />
          <div class="flex flex-col gap-1">
            <span class="mb-0.5 text-heading-3 text-n-slate-12">
              {{ t(`${M}.VALIDADE`) }}
            </span>
            <ChoiceSelect
              data-fidelidade="validade-do-cupom"
              :model-value="cupom.validade_dias"
              :aria-label="t(`${M}.VALIDADE`)"
              :options="validades"
              :invalid="erros.includes('VALIDADE')"
              @update:model-value="validade_dias => mudar({ validade_dias })"
            />
            <p
              v-if="erros.includes('VALIDADE')"
              class="m-0 text-sm text-n-ruby-11"
            >
              {{ msg('VALIDADE') }}
            </p>
          </div>
        </div>

        <p
          role="note"
          class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-blue-12"
        >
          <span
            class="i-lucide-info mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${M}.REGRA_FIXA`) }}
        </p>

        <p
          v-if="erros.length"
          data-fidelidade="erro-geral"
          role="alert"
          class="flex items-start gap-2 px-4 py-3 m-0 text-sm font-medium rounded-xl bg-n-ruby-2 text-n-ruby-12"
        >
          <span
            class="i-lucide-circle-alert mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${M}.ERROS.TUDO`) }}
        </p>

        <div
          class="flex flex-col-reverse gap-3 pt-2 border-t sm:flex-row sm:justify-end border-n-weak"
        >
          <Button
            variant="faded"
            color="slate"
            size="lg"
            class="min-h-11"
            :label="t(`${M}.CANCELAR`)"
            @click="emit('cancelar')"
          />
          <Button
            data-fidelidade="salvar-cupom"
            size="lg"
            class="min-h-11"
            :is-loading="salvando"
            :disabled="salvando"
            :label="t(`${M}.SALVAR`)"
            @click="salvar"
          />
        </div>
      </section>
    </div>
  </div>
</template>
