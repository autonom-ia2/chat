<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../../comum/EsqueletoDeLista.vue';
import {
  ESTADOS_DAS_PALAVRAS as ESTADOS,
  usePalavrasSimples,
} from '../../../carteira/usePalavrasSimples';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';

// #2899 (E6.6) — "Seu seguro em palavras simples", na gaveta do seguro: o que
// o seguro é e quando vence, do jeito que o cliente vai ler. A plataforma
// escreve quando a pessoa pede ("Escrever para <nome>"); a pessoa lê, pode
// alterar e manda. Nada sai sem o clique em "Enviar a <nome>". A última frase
// ("Vale o que está escrito na sua apólice.") vai sempre e não entra no que se
// altera. Sem conversa com o cliente, ou fora do prazo do WhatsApp, não há
// botão desligado: a tela diz por quê e oferece copiar o texto. A cada etapa
// (escrito, alterando) o foco vai ao título dela.
const props = defineProps({
  seguroId: { type: Number, required: true },
  fonte: { type: Object, required: true },
  // O primeiro nome do cliente.
  nome: { type: String, default: '' },
});
const emit = defineEmits(['mudou']);

const MAXIMO = 1000;

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PALAVRAS.${chave}`, valores);
const comNome = chave =>
  props.nome ? tp(chave, { nome: props.nome }) : tp(`${chave}_SEM_NOME`);
const textos = useTextosDoSeguro();
const id = useId();
const raiz = ref(null);
const palavras = usePalavrasSimples(props.fonte, () => props.seguroId);
const { estado, ocupado } = palavras;

const alterando = ref(false);
const rascunho = ref('');
const falta = ref(false);

const dados = computed(() => palavras.palavras.value || {});
const mensagem = computed(() => `${dados.value.texto}\n\n${dados.value.vale}`);
const enviado = computed(() =>
  dados.value.enviadoEm
    ? tp('ENVIADO', {
        data: textos.dataInteira(dados.value.enviadoEm),
        hora: textos.hora(dados.value.enviadoEm),
      })
    : ''
);

// Depois de uma falha, o mesmo botão vira "Tentar de novo".
const rotuloDeEscrever = computed(() =>
  palavras.erro.value
    ? t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')
    : comNome('ESCREVER')
);

const focar = async seletor => {
  await nextTick();
  raiz.value?.querySelector(seletor)?.focus();
};

const escrever = async () => {
  if (await palavras.escrever()) focar('[data-titulo-das-palavras]');
};
const alterar = () => {
  rascunho.value = dados.value.texto;
  falta.value = false;
  alterando.value = true;
  focar('textarea');
};
const voltar = () => {
  alterando.value = false;
  focar('[data-titulo-das-palavras]');
};
const salvar = async () => {
  const texto = rascunho.value.trim();
  falta.value = !texto;
  if (falta.value) {
    focar('textarea');
    return;
  }
  if (await palavras.salvar(texto)) voltar();
};
const enviar = async () => {
  if (await palavras.enviar()) emit('mudou');
};
const copiar = async () => {
  try {
    await navigator.clipboard.writeText(mensagem.value);
    useAlert(tp('COPIADO'));
  } catch {
    useAlert(tp('NAO_COPIOU'));
  }
};

watch(
  () => props.seguroId,
  () => {
    alterando.value = false;
    palavras.carregar();
  },
  { immediate: true }
);
</script>

<template>
  <section
    ref="raiz"
    data-carteira="palavras-simples"
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-3"
  >
    <h3
      :id="`${id}-titulo`"
      data-titulo-das-palavras
      tabindex="-1"
      class="m-0 text-base font-semibold text-n-slate-12 focus:outline-none"
    >
      {{ tp('TITULO') }}
    </h3>

    <EsqueletoDeLista v-if="estado === ESTADOS.CARREGANDO" :linhas="2" />
    <ErroComTentarDeNovo
      v-else-if="estado === ESTADOS.ERRO"
      :mensagem="tp('NAO_ABRIU')"
      @tentar="palavras.carregar"
    />

    <template v-else-if="!dados.texto">
      <p class="m-0 text-base text-n-slate-11">{{ comNome('APOIO') }}</p>
      <p
        v-if="ocupado === 'escrever'"
        role="status"
        data-carteira="palavras-escrevendo"
        class="m-0 text-base text-n-slate-12"
      >
        {{ tp('ESCREVENDO') }}
      </p>
      <Button
        v-else
        faded
        size="lg"
        class="self-start"
        data-carteira="escrever-palavras"
        :label="rotuloDeEscrever"
        @click="escrever"
      />
    </template>

    <template v-else-if="alterando">
      <label :for="`${id}-texto`" class="text-base text-n-slate-12">
        {{ tp('TEXTO') }}
      </label>
      <TextArea
        :id="`${id}-texto`"
        v-model="rascunho"
        auto-height
        :max-length="MAXIMO"
        min-height="6rem"
        max-height="none"
        data-carteira="texto-das-palavras"
        custom-text-area-class="!text-base"
        :message-type="falta ? 'error' : 'info'"
      />
      <p class="m-0 text-sm text-n-slate-11">{{ dados.vale }}</p>
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
          :is-loading="ocupado === 'salvar'"
          :label="tp('SALVAR')"
          @click="salvar"
        />
        <Button
          slate
          faded
          size="lg"
          data-carteira="voltar-das-palavras"
          :label="tp('VOLTAR')"
          @click="voltar"
        />
      </div>
    </template>

    <template v-else>
      <p
        data-carteira="previa-das-palavras"
        class="p-4 m-0 text-base whitespace-pre-line break-words rounded-2xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ mensagem }}
      </p>
      <p
        v-if="enviado"
        data-carteira="palavras-enviadas"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ enviado }}
      </p>
      <p
        v-if="dados.envio !== 'conversa'"
        data-carteira="palavras-sem-envio"
        class="m-0 text-base text-n-slate-12"
      >
        {{
          dados.envio === 'fora_da_janela'
            ? tp('FORA_DA_JANELA')
            : comNome('SEM_CONVERSA')
        }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          v-if="dados.envio === 'conversa'"
          faded
          size="lg"
          data-carteira="enviar-palavras"
          :is-loading="ocupado === 'enviar'"
          :label="comNome(enviado ? 'ENVIAR_DE_NOVO' : 'ENVIAR')"
          @click="enviar"
        />
        <Button
          v-else
          faded
          size="lg"
          icon="i-lucide-copy"
          data-carteira="copiar-palavras"
          :label="tp('COPIAR')"
          @click="copiar"
        />
        <Button
          link
          size="lg"
          class="min-h-11"
          data-carteira="alterar-palavras"
          :label="tp('ALTERAR')"
          @click="alterar"
        />
        <Button
          link
          size="lg"
          class="min-h-11"
          data-carteira="escrever-de-novo"
          :is-loading="ocupado === 'escrever'"
          :label="tp('ESCREVER_DE_NOVO')"
          @click="escrever"
        />
      </div>
    </template>

    <p
      v-if="palavras.erro.value"
      role="alert"
      data-carteira="erro-das-palavras"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ t(palavras.erro.value) }}
    </p>
  </section>
</template>
