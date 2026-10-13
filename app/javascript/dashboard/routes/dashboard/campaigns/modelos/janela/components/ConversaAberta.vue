<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { numero } from '../../helpers/datas';
import { previa } from '../textoComCampos';
import EscreverNaConversaAberta from './EscreverNaConversaAberta.vue';

// Passo Mensagem da campanha do WhatsApp oficial (#1335): quem falou com você
// nas últimas 24 horas pode receber uma mensagem escrita por você, sem modelo.
// Mostra quantos são, quanto se economiza, e abre a ajuda para escrever.
const props = defineProps({
  // useConversaAberta(), criado uma vez na Nova campanha.
  janela: { type: Object, required: true },
  texto: { type: String, default: '' },
  exemplos: { type: Object, default: () => ({}) },
  temModelo: { type: Boolean, default: false },
  // [{ chave, rotulo }] que a mensagem pode usar.
  campos: { type: Array, default: () => [] },
  divulgacao: { type: Boolean, default: false },
});

const emit = defineEmits(['update']);

const NS = 'MODELOS_WHATSAPP.JANELA';
const { t, locale } = useI18n();
const n = valor => numero(valor, locale.value);
const aberta = ref(false);

const contagem = computed(() => props.janela.contagem.value);
const dentro = computed(() => contagem.value?.dentro || 0);
const fora = computed(() => contagem.value?.fora || 0);

const economia = computed(() => {
  const valor =
    props.janela.custoModelo(dentro.value) -
    props.janela.custoEscrita(dentro.value);
  return valor > 0 ? props.janela.dinheiro(valor) : '';
});

// Contrato da #1322: grátis até 1.000 por número no mês; depois, tarifa de serviço.
const custoDaEscrita = computed(() => {
  const resumo = props.janela.resumoDaEscrita(dentro.value);
  return t(`${NS}.CUSTO_ESCRITA.${resumo.tipo}`, {
    ...resumo,
    sobram: n(resumo.sobram ?? 0),
    limite: n(resumo.limite ?? 0),
    pagas: n(resumo.pagas),
    gratis: n(resumo.gratis),
  });
});

const textoDaPrevia = computed(() => previa(props.texto, props.exemplos));

const usar = texto => {
  aberta.value = false;
  emit('update', { textoNaConversaAberta: texto });
};
</script>

<template>
  <section
    data-conversa-aberta
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-2"
    aria-live="polite"
  >
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.TITULO`) }}
    </h3>

    <p
      v-if="janela.carregando.value"
      class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
      role="status"
    >
      <span
        class="i-lucide-loader-circle size-4 animate-spin"
        aria-hidden="true"
      />
      {{ t(`${NS}.CONTANDO`) }}
    </p>

    <p
      v-else-if="contagem && !dentro"
      data-ninguem
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t(`${NS}.NINGUEM`) }}
    </p>

    <template v-else-if="contagem">
      <ul class="grid gap-2 p-0 m-0 list-none sm:grid-cols-2">
        <li
          data-grupo="dentro"
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-5"
        >
          <span class="flex items-center gap-2 text-sm font-semibold">
            <span
              class="i-lucide-message-circle size-5 text-n-teal-11"
              aria-hidden="true"
            />
            <span class="text-n-slate-12">
              {{ t(`${NS}.DENTRO`, { n: n(dentro) }, dentro) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              texto
                ? t(`${NS}.DENTRO_RECEBE_TEXTO`, { custo: custoDaEscrita })
                : t(`${NS}.DENTRO_PODE`)
            }}
          </span>
        </li>
        <li
          data-grupo="fora"
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
        >
          <span class="flex items-center gap-2 text-sm font-semibold">
            <span
              class="i-lucide-file-text size-5 text-n-slate-11"
              aria-hidden="true"
            />
            <span class="text-n-slate-12">
              {{ t(`${NS}.FORA`, { n: n(fora) }, fora) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{ temModelo ? t(`${NS}.FORA_MODELO`) : t(`${NS}.FORA_SEM_MODELO`) }}
          </span>
        </li>
      </ul>

      <p
        v-if="divulgacao"
        data-aviso-propaganda
        class="flex gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
      >
        <span
          class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        {{ t(`${NS}.AVISO_PROPAGANDA`) }}
      </p>

      <div v-if="texto" data-texto-pronto class="flex flex-col gap-3">
        <div class="p-3 rounded-2xl bg-n-teal-2">
          <p
            class="m-0 max-w-md whitespace-pre-wrap break-words rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
          >
            {{ textoDaPrevia }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            data-alterar-texto
            :label="t(`${NS}.ALTERAR`)"
            icon="i-lucide-pencil"
            variant="outline"
            color="slate"
            class="!min-h-11 !rounded-xl"
            @click="aberta = true"
          />
          <Button
            data-tirar-texto
            :label="t(`${NS}.TODOS_MODELO`)"
            variant="ghost"
            color="slate"
            class="!min-h-11 !rounded-xl"
            @click="emit('update', { textoNaConversaAberta: '' })"
          />
        </div>
      </div>

      <div v-else class="flex flex-col gap-2">
        <p v-if="economia" data-economia class="m-0 text-sm text-n-slate-12">
          {{ t(`${NS}.ECONOMIA`, { valor: economia }) }}
        </p>
        <Button
          data-escrever
          :label="t(`${NS}.ESCREVER`, { n: n(dentro) }, dentro)"
          icon="i-lucide-pen-line"
          class="w-full sm:w-auto sm:self-start !min-h-11 !rounded-xl"
          @click="aberta = true"
        />
      </div>

      <p class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.CONFERIMOS`) }}
      </p>
    </template>

    <EscreverNaConversaAberta
      v-if="aberta"
      :quantos="dentro"
      :texto="texto"
      :exemplos="exemplos"
      :escrever="janela.escrever"
      :campos="campos"
      :divulgacao="divulgacao"
      @usar="usar"
      @fechar="aberta = false"
    />
  </section>
</template>
