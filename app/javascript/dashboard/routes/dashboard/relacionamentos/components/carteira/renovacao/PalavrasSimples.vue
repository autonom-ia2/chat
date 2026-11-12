<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import PreviaDeMensagem from './PreviaDeMensagem.vue';

// #2897 — "Seu seguro em palavras simples", na gaveta do seguro de apólice
// nova: o que o seguro cobre e o que fazer se precisar, do jeito que a pessoa
// vai ler. Quem escolheu conferir antes vê o texto, pode alterar e envia; quem
// escolheu "sai sozinho" só vê que já foi ou, se o WhatsApp não deixou sair, a
// mesma frase da proposta que não saiu e "Conversar". A última frase ("Vale o que está
// escrito na sua apólice.") vai sempre e não entra no que se altera. Ao alterar,
// o campo abre do tamanho do texto e cresce com ele: nada fica atrás de uma
// rolagem dentro do campo.
const props = defineProps({
  seguro: { type: Object, required: true },
  // O nome da ação que está rodando ('' = nenhuma).
  ocupado: { type: String, default: '' },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['salvar', 'enviar', 'tentar', 'conversar']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PALAVRAS.${chave}`, valores);
// As frases do envio sozinho que não saiu são as mesmas da proposta.
const daCotacao = chave =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`);
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

    <template v-else-if="palavras.estado === 'nao_saiu'">
      <p
        data-carteira="palavras-nao-saiu"
        class="m-0 text-base text-n-slate-12"
      >
        {{ daCotacao('NAO_SAIU') }}
      </p>
      <div>
        <Button
          faded
          size="lg"
          data-carteira="conversar-sobre-as-palavras"
          :label="daCotacao('CONVERSAR')"
          @click="emit('conversar')"
        />
      </div>
    </template>

    <template v-else-if="alterando">
      <label :for="`${id}-texto`" class="text-base text-n-slate-12">
        {{ tp('TEXTO') }}
      </label>
      <TextArea
        :id="`${id}-texto`"
        v-model="rascunho"
        auto-height
        min-height="6rem"
        max-height="none"
        data-carteira="texto-das-palavras"
        custom-text-area-class="!text-base"
        :message-type="falta ? 'error' : 'info'"
      />
      <p class="m-0 text-sm text-n-slate-11">
        {{ tp('VALE') }}
      </p>
      <p
        v-if="falta"
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
          data-carteira="voltar-das-palavras"
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
