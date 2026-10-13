<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PreviaMoldura from './previas/PreviaMoldura.vue';
import PreviaConversa from './previas/PreviaConversa.vue';
import PreviaCenario from './previas/PreviaCenario.vue';
import PreviaFila from './previas/PreviaFila.vue';
import PreviaOnline from './previas/PreviaOnline.vue';
import PreviaQuando from './previas/PreviaQuando.vue';
import PreviaColunas from './previas/PreviaColunas.vue';
import PreviaQuadro from './previas/PreviaQuadro.vue';
import {
  CENARIO_FORA,
  CENARIO_ONLINE,
  filaDoExemplo,
  nomeDe,
  primeiroNome,
  quemRecebeNoExemplo,
  regraDaEtapa,
} from './passagem';

// #1385 — a coluna da direita: em cada tela, o que acontece de verdade com a cliente de exemplo. Tudo sai do mesmo
// estado do formulário. A conversa de exemplo leva o selo "Prévia" e mostra dois dias (sábado com a equipe fora, terça
// com a equipe online); o quadro do funil, que é real, leva "Agora".
const props = defineProps({
  view: { type: String, required: true },
  passo: { type: Number, default: 0 },
  regra: { type: Object, required: true },
  etapas: { type: Array, required: true },
  etapa: { type: Object, default: null },
  funil: { type: String, default: '' },
  equipe: { type: Array, default: () => [] },
  todas: { type: Array, default: () => [] },
  iaLigada: { type: Boolean, default: true },
  semCaixa: { type: Boolean, default: false },
});

const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';
const cliente = computed(() => t(`${P}.CLIENTE`));
const cenario = ref(CENARIO_FORA);

// Na etapa aberta, a prévia mostra a regra que vale nela; no resto, a do funil.
// Em "Como entregar", a prévia mostra o que vale depois de salvar: a tela sempre salva segurando a conversa até alguém
// ficar online (usePassagemRodape), mesmo quando a regra antiga ainda está gravada.
const naTelaDoComo = computed(
  () => props.view === 'como' || (props.view === 'etapa' && props.passo === 3)
);
const regraMostrada = computed(() => {
  const base =
    props.view === 'etapa' && props.etapa
      ? regraDaEtapa(props.etapa, props.regra)
      : props.regra;
  return naTelaDoComo.value ? { ...base, prefer_online: true } : base;
});
const outra = computed(() =>
  primeiroNome(nomeDe(props.todas, regraMostrada.value.escalation_user_id))
);
const recebe = computed(() =>
  quemRecebeNoExemplo({
    regra: regraMostrada.value,
    equipe: props.equipe,
    todas: props.todas,
    cliente: cliente.value,
    evitar:
      regraMostrada.value.escalation_action === 'escalate' ? outra.value : '',
  })
);
const fila = computed(() => filaDoExemplo(props.equipe, cliente.value));
const naEtapa = computed(() => props.view === 'etapa');
const mostra = computed(() => {
  if (props.view === 'quando' || (naEtapa.value && props.passo === 1))
    return 'quando';
  if (props.view === 'quem' || (naEtapa.value && props.passo === 2))
    return 'quem';
  if (props.view === 'etapas') return 'etapas';
  return 'conversa';
});
// Os dois dias só mudam algo quando a passagem chama a equipe de verdade.
const temDoisDias = computed(
  () =>
    mostra.value === 'conversa' &&
    props.iaLigada &&
    !props.semCaixa &&
    regraMostrada.value.enabled
);
const cenarioMostrado = computed(() =>
  temDoisDias.value ? cenario.value : CENARIO_FORA
);
const textoDoDia = computed(() =>
  t(
    cenarioMostrado.value === CENARIO_ONLINE
      ? `${P}.CONVERSA_TEXTO_ONLINE`
      : `${P}.CONVERSA_TEXTO_FORA`
  )
);
const moldura = computed(() => {
  if (mostra.value === 'quando')
    return { titulo: t(`${P}.QUANDO_TITULO`), texto: t(`${P}.QUANDO_TEXTO`) };
  if (mostra.value === 'quem')
    return { titulo: t(`${P}.QUEM_TITULO`), texto: t(`${P}.QUEM_TEXTO`) };
  if (mostra.value === 'etapas') {
    return {
      titulo: t(`${P}.ETAPAS_TITULO`),
      texto: t(`${P}.ETAPAS_TEXTO`),
      selo: 'agora',
    };
  }
  if (naEtapa.value) {
    return {
      titulo: t(`${P}.ETAPA_TITULO`, { etapa: props.etapa?.nome }),
      texto: textoDoDia.value,
    };
  }
  return { titulo: t(`${P}.CONVERSA_TITULO`), texto: textoDoDia.value };
});
</script>

<template>
  <div class="flex flex-col gap-4 lg:sticky lg:top-7">
    <PreviaMoldura
      :titulo="moldura.titulo"
      :texto="moldura.texto"
      :selo="moldura.selo || 'previa'"
    >
      <PreviaQuadro
        v-if="mostra === 'etapas'"
        :nome="funil"
        :etapas="etapas"
        :regra="regra"
        :pessoas="todas"
      />
      <PreviaColunas
        v-if="naEtapa && passo === 0"
        :nome="funil"
        :etapas="etapas"
        :regra="regra"
        :pessoas="todas"
        :acesa="etapa?.id ?? null"
      />
      <PreviaQuando v-if="mostra === 'quando'" />
      <template v-else-if="mostra === 'quem'">
        <PreviaFila :regra="regraMostrada" :fila="fila" :pessoa="recebe" />
        <PreviaOnline
          v-if="regraMostrada.pool_type !== 'user' || recebe"
          :regra="regraMostrada"
          :fila="fila"
          :pessoa="recebe"
        />
      </template>
      <template v-else-if="mostra === 'conversa'">
        <PreviaCenario v-if="temDoisDias" v-model="cenario" />
        <PreviaConversa
          :regra="regraMostrada"
          :recebe="recebe"
          :outra="outra"
          :ia-ligada="iaLigada"
          :sem-caixa="semCaixa"
          :cenario="cenarioMostrado"
        />
      </template>
      <PreviaColunas
        v-if="view === 'home' && etapas.length"
        :nome="funil"
        :etapas="etapas"
        :regra="regra"
        :pessoas="todas"
        selo="agora"
      />
    </PreviaMoldura>
  </div>
</template>
