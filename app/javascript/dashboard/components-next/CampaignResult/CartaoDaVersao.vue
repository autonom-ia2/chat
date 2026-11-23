<script setup>
// #3099 — uma das duas versões no resultado: o selo ("Ganhou", "Na frente"), o começo da mensagem, os números em
// linhas simples ("Responderam 12 · de cada 100, 12") e, enquanto dá para escolher, o botão que manda esta versão
// para o resto, com a pergunta de confirmação no próprio cartão (sem janela por cima). O cartão "Na frente" leva o
// botão principal (sólido); o foco vai para o "Sim, mandar" ao abrir a pergunta e volta ao botão no "Voltar".
import { nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  numero: { type: Number, required: true },
  texto: { type: String, default: '' },
  // [{ chave, rotulo, valor, apoio (texto ou lista: cada item numa linha), forte }]
  linhas: { type: Array, default: () => [] },
  selo: { type: String, default: '' },
  // O ícone do selo da escolhida: troféu só quando ganhou; "send" no empate e na escolha à mão.
  iconeDoSelo: { type: String, default: '' },
  destaque: { type: Boolean, default: false },
  // A versão na frente: o botão de escolher fica sólido; na outra, contorno.
  principal: { type: Boolean, default: false },
  // Os textos do botão e da confirmação; sem `botao`, o cartão não oferece escolha.
  botao: { type: String, default: '' },
  botaoAria: { type: String, default: '' },
  pergunta: { type: String, default: '' },
  aviso: { type: String, default: '' },
  sim: { type: String, default: '' },
  enviando: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const confirmando = ref(false);
const botaoEscolher = ref(null);
const botaoSim = ref(null);
const focar = alvo => nextTick(() => alvo.value?.$el?.focus());
const abrirPergunta = () => {
  confirmando.value = true;
  focar(botaoSim);
};
const voltar = () => {
  confirmando.value = false;
  focar(botaoEscolher);
};
const apoiosDa = linha => [].concat(linha.apoio || []).filter(Boolean);
</script>

<template>
  <article
    class="flex min-w-0 flex-col gap-4 rounded-2xl border p-4 sm:p-5"
    :class="
      destaque ? 'border-n-teal-8 bg-n-teal-2' : 'border-n-weak bg-n-solid-1'
    "
    :data-cartao-versao="numero"
  >
    <header class="flex min-h-7 items-center justify-between gap-2">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('DUAS_VERSOES.MENSAGEM.VERSAO', { n: numero }) }}
      </h3>
      <span
        v-if="selo"
        class="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold"
        :class="
          destaque
            ? 'bg-n-teal-3 text-n-teal-12 ring-1 ring-n-teal-8'
            : 'bg-n-blue-3 text-n-blue-11'
        "
        data-selo
      >
        <span
          v-if="destaque && iconeDoSelo"
          class="size-3.5"
          :class="iconeDoSelo"
          aria-hidden="true"
          :data-icone-do-selo="iconeDoSelo"
        />
        {{ selo }}
      </span>
    </header>

    <p
      v-if="texto"
      class="m-0 line-clamp-3 whitespace-pre-wrap break-words rounded-xl bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      data-texto-da-versao
    >
      {{ texto }}
    </p>

    <dl class="m-0 flex flex-col gap-2">
      <div
        v-for="linha in linhas"
        :key="linha.chave"
        class="flex items-baseline justify-between gap-3"
        :data-linha="linha.chave"
      >
        <dt class="text-sm text-n-slate-11">{{ linha.rotulo }}</dt>
        <dd class="m-0 flex flex-col items-end text-end">
          <span
            class="tabular-nums text-n-slate-12"
            :class="linha.forte ? 'text-xl font-semibold' : 'text-base'"
          >
            {{ linha.valor }}
          </span>
          <span
            v-for="apoio in apoiosDa(linha)"
            :key="apoio"
            class="text-balance text-xs tabular-nums text-n-slate-11"
          >
            {{ apoio }}
          </span>
        </dd>
      </div>
    </dl>

    <template v-if="botao">
      <Button
        v-if="!confirmando"
        ref="botaoEscolher"
        :label="botao"
        :aria-label="botaoAria || botao"
        :variant="principal ? 'solid' : 'outline'"
        :color="principal ? 'blue' : 'slate'"
        class="!min-h-11 w-full !rounded-xl"
        :data-escolher-versao="principal ? 'principal' : ''"
        @click="abrirPergunta"
      />
      <div
        v-else
        class="flex flex-col gap-3 rounded-xl bg-n-alpha-1 p-3"
        role="group"
        :aria-label="pergunta"
        data-confirmar-versao
      >
        <div class="flex flex-col gap-1">
          <p class="m-0 text-sm font-medium text-n-slate-12">{{ pergunta }}</p>
          <p v-if="aviso" class="m-0 text-xs text-n-slate-11" data-aviso>
            {{ aviso }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            ref="botaoSim"
            :label="sim"
            class="!min-h-11 !rounded-xl"
            :is-loading="enviando"
            data-sim-mandar
            @click="emit('escolher', numero)"
          />
          <Button
            :label="t('DUAS_VERSOES.RESULTADO.VOLTAR')"
            variant="ghost"
            color="slate"
            class="!min-h-11 !rounded-xl"
            :disabled="enviando"
            @click="voltar"
          />
        </div>
      </div>
    </template>
  </article>
</template>
