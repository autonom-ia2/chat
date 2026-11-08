<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import EscolherArquivo from './EscolherArquivo.vue';
import {
  BOTOES_POR_CARTAO,
  CARTOES_MAXIMO,
  CARTOES_MINIMO,
  LIMITE_DO_CARTAO,
} from '../../constants';
import { LIMITE_DO_BOTAO, ordenarBotoes } from '../../helpers/regraEstrutural';

// Carrossel: de 2 a 10 cartões, cada um com foto ou vídeo, um texto curto e
// até 2 botões. O WhatsApp exige os mesmos botões em todos os cartões, então os
// botões são escolhidos uma vez e valem para todos; o texto e o link de cada
// cartão mudam.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const cartoes = computed(() => rascunho.value.conteudo.cartoes);
const tiposDosBotoes = computed(() =>
  (cartoes.value[0]?.botoes || []).map(botao => botao.tipo)
);

const TIPOS = [
  { chave: 'site', icone: 'i-lucide-external-link' },
  { chave: 'resposta', icone: 'i-lucide-reply' },
];
const MIDIAS = [
  { chave: 'foto', icone: 'i-lucide-image', aceita: 'image/jpeg,image/png' },
  {
    chave: 'video',
    icone: 'i-lucide-video',
    aceita: 'video/mp4,video/quicktime,.mp4,.mov',
  },
];

const mudarCartoes = lista => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: { ...rascunho.value.conteudo, cartoes: lista },
  };
};

const mudarCartao = (indice, campos) =>
  mudarCartoes(
    cartoes.value.map((cartao, i) =>
      i === indice ? { ...cartao, ...campos } : cartao
    )
  );

const mudarBotao = (indice, posicao, campo, valor) =>
  mudarCartao(indice, {
    botoes: cartoes.value[indice].botoes.map((botao, p) =>
      p === posicao ? { ...botao, [campo]: valor } : botao
    ),
  });

// Liga ou desliga um tipo de botão em todos os cartões de uma vez.
const alternarTipo = tipo => {
  const ligado = tiposDosBotoes.value.includes(tipo);
  if (!ligado && tiposDosBotoes.value.length >= BOTOES_POR_CARTAO) return;
  mudarCartoes(
    cartoes.value.map(cartao => ({
      ...cartao,
      botoes: ligado
        ? cartao.botoes.filter(botao => botao.tipo !== tipo)
        : ordenarBotoes([...cartao.botoes, { tipo, texto: '', valor: '' }]),
    }))
  );
};

const adicionarCartao = () =>
  mudarCartoes([
    ...cartoes.value,
    {
      midia: 'foto',
      arquivo: '',
      texto: '',
      botoes: tiposDosBotoes.value.map(tipo => ({
        tipo,
        texto: '',
        valor: '',
      })),
    },
  ]);

const tirarCartao = indice =>
  mudarCartoes(cartoes.value.filter((_, i) => i !== indice));

// Arquivo novo: guardado até o envio (sobe para a Meta no "Enviar").
const aoEscolherArquivo = (indice, { arquivo, local }) =>
  mudarCartao(indice, { arquivo, local, handle: '' });
</script>

<template>
  <div data-etapa-cartoes class="flex flex-col gap-6">
    <p class="mb-0 text-base text-n-slate-11">
      {{
        $t('MODELOS_WHATSAPP.CARTOES.INTRO', {
          min: CARTOES_MINIMO,
          max: CARTOES_MAXIMO,
        })
      }}
    </p>

    <section class="flex flex-col gap-3">
      <div>
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.CARTOES.BOTOES') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.CARTOES.BOTOES_AJUDA') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-3">
        <button
          v-for="tipo in TIPOS"
          :key="tipo.chave"
          type="button"
          role="checkbox"
          :data-tipo-dos-cartoes="tipo.chave"
          :aria-checked="tiposDosBotoes.includes(tipo.chave)"
          class="inline-flex items-center gap-2 px-4 text-[0.9375rem] font-medium rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            tiposDosBotoes.includes(tipo.chave)
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
              : 'ring-n-weak bg-n-solid-1 text-n-slate-11 hover:ring-n-blue-6'
          "
          @click="alternarTipo(tipo.chave)"
        >
          <span class="size-4" :class="tipo.icone" aria-hidden="true" />
          {{ $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${tipo.chave}.ROTULO`) }}
        </button>
      </div>
    </section>

    <ol class="flex flex-col gap-4 p-0 m-0 list-none">
      <li
        v-for="(cartao, indice) in cartoes"
        :key="indice"
        :data-cartao="indice + 1"
        class="flex flex-col gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-base font-semibold text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.CARTOES.CARTAO', { n: indice + 1 }) }}
          </h3>
          <Button
            v-if="cartoes.length > CARTOES_MINIMO"
            :label="$t('MODELOS_WHATSAPP.CARTOES.TIRAR')"
            icon="i-lucide-x"
            color="slate"
            variant="ghost"
            size="sm"
            class="min-h-11"
            @click="tirarCartao(indice)"
          />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <button
            v-for="midia in MIDIAS"
            :key="midia.chave"
            type="button"
            role="radio"
            :aria-checked="cartao.midia === midia.chave"
            class="inline-flex items-center gap-2 px-3 text-sm font-medium rounded-lg min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              cartao.midia === midia.chave
                ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
                : 'ring-n-weak text-n-slate-11'
            "
            @click="
              mudarCartao(indice, {
                midia: midia.chave,
                arquivo: '',
                local: '',
                handle: '',
              })
            "
          >
            <span class="size-4" :class="midia.icone" aria-hidden="true" />
            {{ $t(`MODELOS_WHATSAPP.TOPOS.${midia.chave}.ROTULO`) }}
          </button>
          <span v-if="cartao.arquivo" class="text-sm break-all text-n-slate-12">
            {{ cartao.arquivo }}
          </span>
          <EscolherArquivo
            :nome="cartao.arquivo"
            :aceita="MIDIAS.find(m => m.chave === cartao.midia).aceita"
            @escolhido="escolhido => aoEscolherArquivo(indice, escolhido)"
          />
        </div>
        <TextArea
          :model-value="cartao.texto"
          :label="$t('MODELOS_WHATSAPP.CARTOES.TEXTO')"
          :max-length="LIMITE_DO_CARTAO"
          show-character-count
          @update:model-value="valor => mudarCartao(indice, { texto: valor })"
        />
        <div
          v-for="(botao, posicao) in cartao.botoes"
          :key="posicao"
          class="grid gap-3 sm:grid-cols-2"
        >
          <Input
            wrap-message
            :model-value="botao.texto"
            :maxlength="LIMITE_DO_BOTAO"
            :message="
              $t('MODELOS_WHATSAPP.EXTRAS.LIMITE_DO_BOTAO', {
                n: (botao.texto || '').length,
                limite: LIMITE_DO_BOTAO,
              })
            "
            :message-type="
              (botao.texto || '').length > LIMITE_DO_BOTAO ? 'error' : 'info'
            "
            :label="$t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.ROTULO`)"
            :placeholder="
              $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.EXEMPLO`)
            "
            @update:model-value="
              valor => mudarBotao(indice, posicao, 'texto', valor)
            "
          />
          <Input
            v-if="botao.tipo === 'site'"
            :model-value="botao.valor"
            :label="$t('MODELOS_WHATSAPP.TIPOS_DE_BOTAO.site.VALOR')"
            :placeholder="
              $t('MODELOS_WHATSAPP.TIPOS_DE_BOTAO.site.VALOR_EXEMPLO')
            "
            @update:model-value="
              valor => mudarBotao(indice, posicao, 'valor', valor)
            "
          />
        </div>
      </li>
    </ol>

    <Button
      v-if="cartoes.length < CARTOES_MAXIMO"
      data-adicionar-cartao
      :label="$t('MODELOS_WHATSAPP.CARTOES.ADICIONAR')"
      icon="i-lucide-plus"
      color="slate"
      variant="faded"
      class="self-start min-h-11"
      @click="adicionarCartao"
    />
  </div>
</template>
