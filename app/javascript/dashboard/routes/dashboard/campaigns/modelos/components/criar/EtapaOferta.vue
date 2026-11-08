<script setup>
import { andarComSetas } from '../../helpers/setas';
import { computed } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { LIMITE_DO_TITULO_DA_OFERTA } from '../../constants';
import EscolherArquivo from './EscolherArquivo.vue';

// Oferta por tempo limitado: título, o link (obrigatório) e, se quiser, um
// cupom. Com cupom, o WhatsApp mostra quanto tempo falta (a data de fim é dada
// no envio, não no modelo; a campanha ainda não envia oferta).
// é opcional; rodapé este formato não tem.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const oferta = computed(() => rascunho.value.conteudo.oferta);
const topo = computed(() => rascunho.value.conteudo.topo.tipo);

const TOPOS_DA_OFERTA = [
  { chave: 'nenhum', icone: 'i-lucide-ban' },
  { chave: 'foto', icone: 'i-lucide-image' },
  { chave: 'video', icone: 'i-lucide-video' },
];

const mudarOferta = (campo, valor) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...rascunho.value.conteudo,
      oferta: { ...oferta.value, [campo]: valor },
    },
  };
};

const mudarTopo = tipo => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: { ...rascunho.value.conteudo, topo: { tipo, arquivo: '' } },
  };
};

const ACEITA = {
  foto: 'image/jpeg,image/png',
  video: 'video/mp4,video/quicktime,.mp4,.mov',
};

const aoEscolherArquivo = ({ arquivo, local }) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...rascunho.value.conteudo,
      topo: { tipo: topo.value, arquivo, local },
    },
  };
};

const tituloLongo = computed(
  () => oferta.value.titulo.length > LIMITE_DO_TITULO_DA_OFERTA
);
</script>

<template>
  <div data-etapa-oferta class="flex flex-col gap-6">
    <p class="mb-0 text-base text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.OFERTA.INTRO') }}
    </p>
    <Input
      wrap-message
      :model-value="oferta.titulo"
      data-oferta-titulo
      :label="$t('MODELOS_WHATSAPP.OFERTA.TITULO')"
      :message="
        $t('MODELOS_WHATSAPP.OFERTA.TITULO_LIMITE', {
          n: oferta.titulo.length,
          limite: LIMITE_DO_TITULO_DA_OFERTA,
        })
      "
      :message-type="tituloLongo ? 'error' : 'info'"
      @update:model-value="valor => mudarOferta('titulo', valor)"
    />
    <Input
      wrap-message
      :model-value="oferta.link"
      data-oferta-link
      :label="$t('MODELOS_WHATSAPP.OFERTA.LINK')"
      :placeholder="$t('MODELOS_WHATSAPP.TIPOS_DE_BOTAO.site.VALOR_EXEMPLO')"
      :message="
        oferta.link ? '' : $t('MODELOS_WHATSAPP.OFERTA.LINK_OBRIGATORIO')
      "
      :message-type="oferta.link ? 'info' : 'error'"
      @update:model-value="valor => mudarOferta('link', valor)"
    />
    <Input
      wrap-message
      :model-value="oferta.cupom"
      data-oferta-cupom
      :label="$t('MODELOS_WHATSAPP.OFERTA.CUPOM')"
      :message="$t('MODELOS_WHATSAPP.OFERTA.CUPOM_AJUDA')"
      @update:model-value="valor => mudarOferta('cupom', valor)"
    />
    <section class="flex flex-col gap-3">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.EXTRAS.TOPO') }}
      </h2>
      <div
        role="radiogroup"
        :aria-label="$t('MODELOS_WHATSAPP.EXTRAS.TOPO')"
        class="grid grid-cols-3 gap-3"
        @keydown="andarComSetas"
      >
        <button
          v-for="item in TOPOS_DA_OFERTA"
          :key="item.chave"
          type="button"
          role="radio"
          :aria-checked="topo === item.chave"
          class="flex flex-col items-center justify-center gap-2 p-3 text-[0.9375rem] font-medium rounded-xl min-h-[4.5rem] ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            topo === item.chave
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
              : 'ring-n-weak bg-n-solid-1 text-n-slate-11 hover:ring-n-blue-6'
          "
          @click="mudarTopo(item.chave)"
        >
          <span class="size-5" :class="item.icone" aria-hidden="true" />
          {{ $t(`MODELOS_WHATSAPP.TOPOS.${item.chave}.ROTULO`) }}
        </button>
      </div>
      <div
        v-if="topo !== 'nenhum'"
        class="flex flex-wrap items-center gap-3 p-4 rounded-xl bg-n-slate-2"
      >
        <span class="text-[0.9375rem] text-n-slate-12 break-all">
          {{
            rascunho.conteudo.topo.arquivo ||
            $t(`MODELOS_WHATSAPP.TOPOS.${topo}.AJUDA`)
          }}
        </span>
        <EscolherArquivo
          :nome="rascunho.conteudo.topo.arquivo"
          :aceita="ACEITA[topo]"
          @escolhido="aoEscolherArquivo"
        />
      </div>
    </section>
  </div>
</template>
