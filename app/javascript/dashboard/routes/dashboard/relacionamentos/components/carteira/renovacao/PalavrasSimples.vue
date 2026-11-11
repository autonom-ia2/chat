<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import PreviaDeMensagem from './PreviaDeMensagem.vue';

// #2897 — "Seu seguro em palavras simples", na gaveta do seguro de apólice
// nova: o que o seguro cobre e o que fazer se precisar, do jeito que a pessoa
// vai ler. Quem escolheu conferir antes vê o texto, pode alterar e envia; quem
// escolheu "sai sozinho" só vê que já foi. A última frase ("Vale o que está
// escrito na sua apólice.") vai sempre e não entra no que se altera.
const props = defineProps({
  seguro: { type: Object, required: true },
  // O nome da ação que está rodando ('' = nenhuma).
  ocupado: { type: String, default: '' },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['salvar', 'enviar', 'tentar']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PALAVRAS.${chave}`, valores);
const textos = useTextosDoSeguro();
const id = useId();

const palavras = computed(() => props.seguro.palavras);
const nome = computed(() => props.seguro.pessoa.name.split(' ')[0]);
const escritoPelaCasa = computed(() =>
  [
    tp('OI', {
      nome: nome.value,
      tipo: textos.tipo(props.seguro),
      seguradora: props.seguro.seguradora,
      data: textos.diaMes(props.seguro.comeca, props.agora),
    }),
    tp('COBRE', { cobre: palavras.value.cobre }),
    tp('SE_ACONTECER'),
  ].join('\n')
);
// O que se pode alterar; a última frase entra depois, sempre.
const corpo = computed(() => palavras.value.texto || escritoPelaCasa.value);
const mensagem = computed(() => `${corpo.value}\n${tp('VALE')}`);
const enviado = computed(() => {
  const { enviadoEm, sozinho } = palavras.value;
  if (!enviadoEm) return '';
  return tp(sozinho ? 'ENVIADO_SOZINHO' : 'ENVIADO', {
    data: textos.diaMes(enviadoEm, props.agora),
    hora: textos.hora(enviadoEm),
  });
});

const mostrandoEnviado = ref(false);
const alterando = ref(false);
const rascunho = ref('');
const falta = ref(false);

const alterar = async () => {
  rascunho.value = corpo.value;
  falta.value = false;
  alterando.value = true;
  await nextTick();
  document.getElementById(`${id}-texto`)?.focus();
};
const salvar = () => {
  const texto = rascunho.value.trim();
  falta.value = !texto;
  if (falta.value) {
    document.getElementById(`${id}-texto`)?.focus();
    return;
  }
  alterando.value = false;
  emit('salvar', texto);
};
</script>

<template>
  <section
    data-carteira="palavras-simples"
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-3"
  >
    <h3
      :id="`${id}-titulo`"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ tp('TITULO') }}
    </h3>

    <p
      v-if="palavras.estado === 'lendo'"
      data-carteira="palavras-lendo"
      role="status"
      class="m-0 text-base text-n-slate-11"
    >
      {{ tp('LENDO') }}
    </p>
    <div
      v-else-if="palavras.estado === 'erro'"
      data-carteira="palavras-erro"
      role="alert"
      class="flex flex-col items-start gap-3"
    >
      <p class="m-0 text-base text-n-slate-12">{{ tp('ERRO') }}</p>
      <Button
        slate
        faded
        size="lg"
        :label="tp('TENTAR')"
        @click="emit('tentar')"
      />
    </div>

    <template v-else-if="enviado">
      <p data-carteira="palavras-enviado" class="m-0 text-base text-n-slate-12">
        {{ enviado }}
      </p>
      <div>
        <Button
          link
          size="lg"
          data-carteira="ver-palavras-enviadas"
          :aria-expanded="mostrandoEnviado ? 'true' : 'false'"
          :aria-controls="`${id}-enviado`"
          :label="tp(mostrandoEnviado ? 'ESCONDER' : 'VER_ENVIADO')"
          @click="mostrandoEnviado = !mostrandoEnviado"
        />
      </div>
      <div :id="`${id}-enviado`">
        <PreviaDeMensagem v-if="mostrandoEnviado" :texto="mensagem" />
      </div>
    </template>

    <template v-else-if="alterando">
      <label :for="`${id}-texto`" class="text-base text-n-slate-12">
        {{ tp('TEXTO') }}
      </label>
      <textarea
        :id="`${id}-texto`"
        v-model="rascunho"
        rows="6"
        data-carteira="texto-das-palavras"
        :aria-invalid="falta ? 'true' : undefined"
        :aria-describedby="`${id}-vale ${falta ? `${id}-falta` : ''}`"
        class="block w-full px-3 py-2.5 text-base border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 focus:outline-n-brand"
        :class="falta ? 'outline-n-ruby-8' : 'outline-n-weak'"
      />
      <p :id="`${id}-vale`" class="m-0 text-sm text-n-slate-11">
        {{ tp('VALE') }}
      </p>
      <p
        v-if="falta"
        :id="`${id}-falta`"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ tp('FALTA_TEXTO') }}
      </p>
      <div class="flex flex-wrap gap-3">
        <Button
          faded
          size="lg"
          data-carteira="salvar-palavras"
          :is-loading="ocupado === 'salvarPalavras'"
          :label="tp('SALVAR')"
          @click="salvar"
        />
        <Button
          slate
          faded
          size="lg"
          :label="tp('VOLTAR')"
          @click="alterando = false"
        />
      </div>
    </template>

    <template v-else>
      <PreviaDeMensagem :texto="mensagem" />
      <div class="flex flex-wrap gap-3">
        <Button
          faded
          size="lg"
          data-carteira="enviar-palavras"
          :is-loading="ocupado === 'enviarPalavras'"
          :label="tp('ENVIAR_A', { nome })"
          @click="emit('enviar')"
        />
        <Button
          link
          size="lg"
          data-carteira="alterar-palavras"
          :label="tp('ALTERAR')"
          @click="alterar"
        />
      </div>
    </template>
  </section>
</template>
