<script setup>
import { computed } from 'vue';
import FunilQuadro from './FunilQuadro.vue';
import PreviaMoldura from './previas/PreviaMoldura.vue';
import PreviaComoAnda from './previas/PreviaComoAnda.vue';
import PreviaEtapa from './previas/PreviaEtapa.vue';
import PreviaSobre from './previas/PreviaSobre.vue';
import PreviaVendas from './previas/PreviaVendas.vue';
import PreviaLembretes from './previas/PreviaLembretes.vue';
import PreviaLembretesAtender from './previas/PreviaLembretesAtender.vue';
import PreviaCaixa from './previas/PreviaCaixa.vue';
import PreviaAnuncios from './previas/PreviaAnuncios.vue';

// #1384 — a coluna da direita: em cada tela, a prévia do que muda, tirada do
// mesmo estado do formulário. No resumo de um funil que já existe, o selo diz
// "Agora", porque mostra o quadro de verdade.
const props = defineProps({
  view: { type: String, required: true },
  editando: { type: Boolean, default: false },
  ia: { type: Boolean, default: false },
  nome: { type: String, default: '' },
  quadro: { type: Array, required: true },
  acesa: { type: Number, default: -1 },
  chegando: { type: Number, default: -1 },
  etapa: { type: Object, default: null },
  frase: { type: String, default: '' },
  sugestao: { type: String, default: '' },
  quandoUsar: { type: String, default: '' },
  venda: { type: Boolean, default: true },
  meta: { type: Number, default: 0 },
  sucesso: { type: String, default: '' },
  fracasso: { type: String, default: '' },
  dinheiro: { type: Function, required: true },
  retorno: { type: Object, default: null },
  mensagemNoDia: { type: Boolean, default: false },
  foco: { type: Object, default: null },
  metaSync: { type: Object, required: true },
  googleSync: { type: Object, required: true },
  etapaAvisada: { type: String, default: '' },
  // #1498 — sem tipo escolhido, o funil novo ainda não tem quadro.
  semTipo: { type: Boolean, default: false },
  // #1498 — prévia dos lembretes de Atender.
  lembretesAtender: { type: Object, default: null },
  modelo: { type: String, default: '' },
});

const P = 'CRM_FUNIL.PREVIA';
const em = (...views) => views.includes(props.view);
const primeira = computed(() => props.quadro[0]?.nome || '');
// No passo a passo do Google, a prévia já mostra o que ele vai receber.
const google = computed(() =>
  props.view === 'ads-google'
    ? { ...props.googleSync, enabled: true }
    : props.googleSync
);
</script>

<template>
  <div class="flex flex-col gap-4 lg:sticky lg:top-7">
    <PreviaMoldura
      v-if="em('stage', 'stage-actions')"
      :titulo="$t(`${P}.ETAPA_TITULO`)"
      :texto="$t(`${P}.ETAPA_TEXTO`)"
    >
      <FunilQuadro
        :nome="nome"
        :etapas="quadro"
        :acesa="acesa"
        :exemplo="$t(`${P}.CLIENTE`)"
      />
      <PreviaEtapa
        :nome="etapa?.name"
        :cor="etapa?.color"
        :frase="frase"
        :sugestao="sugestao"
      />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('about')"
      :titulo="$t(`${P}.SOBRE_TITULO`)"
      :texto="$t(`${P}.SOBRE_TEXTO`)"
    >
      <PreviaSobre :nome="nome" :texto="quandoUsar" />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('nome') && semTipo"
      :titulo="$t('CRM_FUNIL.TIPO.PREVIA_TITULO')"
      :texto="$t('CRM_FUNIL.TIPO.PREVIA_TEXTO')"
    >
      <div
        class="grid h-48 grid-cols-4 gap-2 rounded-2xl border-2 border-dashed border-n-slate-6 p-3"
        aria-hidden="true"
      >
        <span
          v-for="coluna in 4"
          :key="coluna"
          class="rounded-xl bg-n-alpha-2"
        />
      </div>
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('sales')"
      :titulo="$t(venda ? `${P}.VENDAS_TITULO` : `${P}.FIM`)"
      :texto="venda ? $t(`${P}.VENDAS_TEXTO`) : ''"
    >
      <PreviaVendas
        :venda="venda"
        :meta="meta"
        :sucesso="sucesso"
        :fracasso="fracasso"
        :dinheiro="dinheiro"
      />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('returns') && !venda"
      :titulo="$t('CRM_FUNIL.ATENDER.LEMBRETES.PREVIA_TITULO')"
      :texto="$t('CRM_FUNIL.ATENDER.LEMBRETES.PREVIA_TEXTO')"
    >
      <PreviaLembretesAtender
        :modelo="modelo"
        :sucesso="sucesso"
        :ligados="lembretesAtender || {}"
      />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('returns', 'returns-detail')"
      :titulo="$t(`${P}.RETORNO_TITULO`)"
      :texto="$t(`${P}.RETORNO_TEXTO`)"
    >
      <PreviaLembretes
        v-if="retorno"
        :retorno="retorno"
        :mensagem-no-dia="mensagemNoDia"
      />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('inboxes')"
      :titulo="$t(`${P}.CAIXA_TITULO`)"
      :texto="$t(`${P}.CAIXA_TEXTO`)"
    >
      <FunilQuadro
        :nome="nome"
        :etapas="quadro"
        :chegando="chegando"
        :exemplo="$t(`${P}.CLIENTE`)"
      />
      <PreviaCaixa :foco="foco" />
    </PreviaMoldura>
    <PreviaMoldura
      v-else-if="em('ads', 'ads-facebook', 'ads-google')"
      :titulo="$t(`${P}.ANUNCIO_TITULO`)"
      :texto="$t(`${P}.ANUNCIO_TEXTO`)"
    >
      <PreviaAnuncios
        :meta="metaSync"
        :google="google"
        :so-google="view === 'ads-google'"
        :etapa-avisada="metaSync.events.moved ? etapaAvisada : ''"
        :resultado="sucesso"
        :dinheiro="dinheiro"
      />
    </PreviaMoldura>
    <PreviaMoldura
      v-else
      :agora="view === 'home'"
      :titulo="$t(editando ? `${P}.HOJE_TITULO` : `${P}.NOVO_TITULO`)"
      :texto="$t(editando ? `${P}.HOJE_TEXTO` : `${P}.NOVO_TEXTO`)"
    >
      <FunilQuadro
        :nome="nome"
        :etapas="quadro"
        :chegando="chegando"
        :exemplo="$t(`${P}.CLIENTE`)"
      />
      <PreviaComoAnda :primeira="primeira" :ia="ia" />
    </PreviaMoldura>
  </div>
</template>
