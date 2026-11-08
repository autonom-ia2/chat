<script setup>
import { andarComSetas } from '../../helpers/setas';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import EscolherArquivo from './EscolherArquivo.vue';
import {
  LIMITE_DO_RODAPE,
  MAXIMO_DE_BOTOES,
  TIPOS_DE_BOTAO,
  TOPOS,
} from '../../constants';
import {
  BOTOES_SO_DE_DIVULGACAO,
  LIMITE_DO_BOTAO,
  ordenarBotoes,
  problemasDoBotao,
} from '../../helpers/regraEstrutural';

// Tudo opcional: foto/vídeo/documento no topo, rodapé e botões.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const { t } = useI18n();
const conteudo = computed(() => rascunho.value.conteudo);
const escolhendoBotao = ref(false);

const mudar = (campo, valor) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: { ...conteudo.value, [campo]: valor },
  };
};

const escolherTopo = tipo => mudar('topo', { tipo, arquivo: '' });

const ACEITA = {
  foto: 'image/jpeg,image/png',
  video: 'video/mp4,video/quicktime,.mp4,.mov',
  documento: 'application/pdf',
};

// Arquivo novo: guardado até o envio (sobe para a Meta no "Enviar").
const aoEscolherArquivo = ({ arquivo, local }) =>
  mudar('topo', { tipo: conteudo.value.topo.tipo, arquivo, local });

const quantosDoTipo = tipo =>
  conteudo.value.botoes.filter(botao => botao.tipo === tipo).length;

// "Copiar código" só existe em divulgação: num aviso, nem aparece para escolher.
const tipoDisponivel = tipo =>
  conteudo.value.botoes.length < MAXIMO_DE_BOTOES &&
  quantosDoTipo(tipo.chave) < tipo.maximo &&
  (rascunho.value.tipo === 'divulgacao' ||
    !BOTOES_SO_DE_DIVULGACAO.includes(tipo.chave));

// O que falta em cada botão, dito no próprio campo (a mesma regra da conferência).
const problemas = botao => problemasDoBotao(botao, rascunho.value.tipo);
const PROBLEMAS_DO_VALOR = [
  'SITE_SEM_ENDERECO',
  'SITE_SEM_EXEMPLO',
  'LIGAR_SEM_NUMERO',
  'CODIGO_SEM_EXEMPLO',
];
const mensagem = (botao, codigos) => {
  const codigo = problemas(botao).find(item => codigos.includes(item));
  return codigo
    ? t(`MODELOS_WHATSAPP.EXTRAS.PROBLEMAS_DO_BOTAO.${codigo}`)
    : '';
};

const adicionarBotao = tipo => {
  mudar(
    'botoes',
    ordenarBotoes([...conteudo.value.botoes, { tipo, texto: '', valor: '' }])
  );
  escolhendoBotao.value = false;
};

const mudarBotao = (indice, campo, valor) =>
  mudar(
    'botoes',
    conteudo.value.botoes.map((botao, i) =>
      i === indice ? { ...botao, [campo]: valor } : botao
    )
  );

const tirarBotao = indice =>
  mudar(
    'botoes',
    conteudo.value.botoes.filter((_, i) => i !== indice)
  );

const iconeDoBotao = tipo =>
  TIPOS_DE_BOTAO.find(item => item.chave === tipo)?.icone;
</script>

<template>
  <div data-etapa-extras class="flex flex-col gap-8">
    <p class="mb-0 text-base text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.EXTRAS.INTRO') }}
    </p>

    <section class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.EXTRAS.TOPO') }}
        </h2>
        <!-- #1394: o topo é igual para todos; documento de cada cliente não vai aqui. -->
        <p data-topo-ajuda class="mb-0 text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.EXTRAS.TOPO_AJUDA') }}
        </p>
      </div>
      <div
        role="radiogroup"
        :aria-label="$t('MODELOS_WHATSAPP.EXTRAS.TOPO')"
        class="grid grid-cols-2 gap-3 sm:grid-cols-4"
        @keydown="andarComSetas"
      >
        <button
          v-for="topo in TOPOS"
          :key="topo.chave"
          type="button"
          role="radio"
          :data-topo="topo.chave"
          :aria-checked="conteudo.topo.tipo === topo.chave"
          class="flex flex-col items-center justify-center gap-2 p-4 text-[0.9375rem] font-medium rounded-xl min-h-[5.5rem] ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            conteudo.topo.tipo === topo.chave
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
              : 'ring-n-weak bg-n-solid-1 text-n-slate-11 hover:ring-n-blue-6'
          "
          @click="escolherTopo(topo.chave)"
        >
          <span class="size-6" :class="topo.icone" aria-hidden="true" />
          {{ $t(`MODELOS_WHATSAPP.TOPOS.${topo.chave}.ROTULO`) }}
        </button>
      </div>
      <p
        v-if="conteudo.topo.tipo === 'texto'"
        data-topo-texto
        class="flex flex-col gap-1 p-4 mb-0 rounded-xl bg-n-slate-2"
      >
        <strong class="text-[0.9375rem] break-words text-n-slate-12">
          {{ conteudo.topo.texto }}
        </strong>
        <span class="text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.TOPOS.texto.AJUDA') }}
        </span>
      </p>
      <div
        v-else-if="conteudo.topo.tipo !== 'nenhum'"
        class="flex flex-wrap items-center gap-3 p-4 rounded-xl bg-n-slate-2"
      >
        <span class="text-[0.9375rem] text-n-slate-12 break-words">
          {{
            conteudo.topo.arquivo ||
            $t(`MODELOS_WHATSAPP.TOPOS.${conteudo.topo.tipo}.AJUDA`)
          }}
        </span>
        <EscolherArquivo
          :nome="conteudo.topo.arquivo"
          :aceita="ACEITA[conteudo.topo.tipo]"
          @escolhido="aoEscolherArquivo"
        />
      </div>
    </section>

    <section class="flex flex-col gap-3">
      <Input
        wrap-message
        :model-value="conteudo.rodape"
        data-rodape
        :label="$t('MODELOS_WHATSAPP.EXTRAS.RODAPE')"
        :placeholder="$t('MODELOS_WHATSAPP.EXTRAS.RODAPE_EXEMPLO')"
        :message="
          $t('MODELOS_WHATSAPP.EXTRAS.RODAPE_LIMITE', {
            n: conteudo.rodape.length,
            limite: LIMITE_DO_RODAPE,
          })
        "
        :message-type="
          conteudo.rodape.length > LIMITE_DO_RODAPE ? 'error' : 'info'
        "
        @update:model-value="valor => mudar('rodape', valor)"
      />
    </section>

    <section class="flex flex-col gap-3">
      <div>
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.EXTRAS.BOTOES') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.EXTRAS.BOTOES_LIMITE') }}
        </p>
      </div>
      <ul
        v-if="conteudo.botoes.length"
        class="flex flex-col gap-3 p-0 m-0 list-none"
      >
        <li
          v-for="(botao, indice) in conteudo.botoes"
          :key="indice"
          :data-botao="botao.tipo"
          class="flex flex-col gap-3 p-4 rounded-xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between gap-3">
            <span
              class="inline-flex items-center gap-2 text-sm font-medium text-n-slate-11"
            >
              <span
                class="size-4"
                :class="iconeDoBotao(botao.tipo)"
                aria-hidden="true"
              />
              {{ $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.ROTULO`) }}
            </span>
            <Button
              :label="$t('MODELOS_WHATSAPP.EXTRAS.TIRAR_BOTAO')"
              icon="i-lucide-x"
              color="slate"
              variant="ghost"
              size="sm"
              class="min-h-11"
              @click="tirarBotao(indice)"
            />
          </div>
          <p
            v-if="problemas(botao).includes('SO_DIVULGACAO')"
            data-so-divulgacao
            role="alert"
            class="flex items-start gap-2 p-3 mb-0 text-[0.9375rem] font-medium rounded-lg bg-n-ruby-2 text-n-ruby-11"
          >
            <span
              class="i-lucide-circle-alert size-5 mt-0.5 shrink-0"
              aria-hidden="true"
            />
            {{ $t('MODELOS_WHATSAPP.EXTRAS.PROBLEMAS_DO_BOTAO.SO_DIVULGACAO') }}
          </p>
          <div v-else class="grid gap-3 sm:grid-cols-2">
            <Input
              v-if="botao.tipo !== 'copiar_codigo'"
              wrap-message
              :model-value="botao.texto"
              :maxlength="LIMITE_DO_BOTAO"
              :message="
                mensagem(botao, ['SEM_TEXTO', 'TEXTO_LONGO']) ||
                $t('MODELOS_WHATSAPP.EXTRAS.LIMITE_DO_BOTAO', {
                  n: (botao.texto || '').length,
                  limite: LIMITE_DO_BOTAO,
                })
              "
              :message-type="
                mensagem(botao, ['SEM_TEXTO', 'TEXTO_LONGO']) ? 'error' : 'info'
              "
              :label="$t('MODELOS_WHATSAPP.EXTRAS.TEXTO_DO_BOTAO')"
              :placeholder="
                $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.EXEMPLO`)
              "
              @update:model-value="valor => mudarBotao(indice, 'texto', valor)"
            />
            <!-- O número do "Ligar" no campo de telefone padrão (#1900): país e
                 DDI à vista; o valor só chega em E.164 quando é válido. -->
            <CampoDeTelefone
              v-if="botao.tipo === 'ligar'"
              :model-value="botao.valor"
              :label="$t('MODELOS_WHATSAPP.TIPOS_DE_BOTAO.ligar.VALOR')"
              :rotulo-do-pais="$t('MODELOS_WHATSAPP.TIPOS_DE_BOTAO.ligar.PAIS')"
              :erro="mensagem(botao, PROBLEMAS_DO_VALOR)"
              @update:model-value="valor => mudarBotao(indice, 'valor', valor)"
            />
            <Input
              v-else-if="['site', 'copiar_codigo'].includes(botao.tipo)"
              wrap-message
              :model-value="botao.valor"
              :label="$t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.VALOR`)"
              :message="mensagem(botao, PROBLEMAS_DO_VALOR)"
              :message-type="
                mensagem(botao, PROBLEMAS_DO_VALOR) ? 'error' : 'info'
              "
              :placeholder="
                $t(
                  `MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${botao.tipo}.VALOR_EXEMPLO`
                )
              "
              @update:model-value="valor => mudarBotao(indice, 'valor', valor)"
            />
          </div>
        </li>
      </ul>

      <div
        v-if="escolhendoBotao"
        data-tipos-de-botao
        class="grid gap-3 sm:grid-cols-2"
      >
        <button
          v-for="tipo in TIPOS_DE_BOTAO"
          :key="tipo.chave"
          type="button"
          :data-tipo-botao="tipo.chave"
          :disabled="!tipoDisponivel(tipo)"
          class="flex items-start gap-3 p-4 text-start rounded-xl ring-1 ring-inset ring-n-weak bg-n-solid-1 min-h-11 hover:ring-n-blue-7 disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="adicionarBotao(tipo.chave)"
        >
          <span
            class="grid place-items-center size-10 shrink-0 rounded-lg bg-n-blue-2 text-n-blue-11"
          >
            <span class="size-5" :class="tipo.icone" aria-hidden="true" />
          </span>
          <span class="flex flex-col gap-0.5">
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${tipo.chave}.ROTULO`) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ $t(`MODELOS_WHATSAPP.TIPOS_DE_BOTAO.${tipo.chave}.PARA`) }}
            </span>
          </span>
        </button>
      </div>
      <Button
        v-else-if="conteudo.botoes.length < MAXIMO_DE_BOTOES"
        data-adicionar-botao
        :label="$t('MODELOS_WHATSAPP.EXTRAS.ADICIONAR_BOTAO')"
        icon="i-lucide-plus"
        color="slate"
        variant="faded"
        class="self-start min-h-11"
        @click="escolhendoBotao = true"
      />
    </section>
  </div>
</template>
