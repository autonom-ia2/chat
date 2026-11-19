<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { destinoDoCard } from '../../carteira/cardNoCrm';
import {
  caixaEscolhida,
  emReais,
  nomeDaCaixaNaFrase,
} from '../../carteira/cotacaoDaRenovacao';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import { renovacoesFonteReal } from '../../fonte/renovacoesFonteReal';
import DialogoDeConfirmacao from './DialogoDeConfirmacao.vue';

// #3057 — a pergunta antes de "Enviar proposta", na gaveta do seguro: para
// quem vai ("Vai para Ana pelo WhatsApp Vendas"), o link para ver o PDF da
// proposta e "Enviar agora" ou "Voltar". Nada sai antes do "Enviar agora";
// quem manda é a gaveta, pelo mesmo pedido de sempre.
// O WhatsApp é o que a conta escolheu em "Ajustar renovações" (é por ele que a
// proposta sai): a pergunta lê os ajustes ao abrir. Se não deu para ler (ou na
// demonstração), a frase diz só "pelo WhatsApp das renovações".
// O PDF da proposta mora no card da renovação, no CRM (o servidor o guarda lá,
// numa nota que o cliente não vê): o link abre o card em outra aba, e a
// pergunta continua aberta aqui.
// #3057 (2ª rodada) — a frase diz tudo o que vai: "Vai para Ana pelo WhatsApp
// Vendas: a proposta de R$ 1.234,00, da Porto, com o PDF." (valor e
// seguradora são os da cotação que a gaveta já tem). O nome do WhatsApp é lido
// ANTES de abrir a pergunta (`abrir` espera a leitura), para a frase não pular
// de "das renovações" para o nome com ela aberta. O link diz para onde leva: a
// proposta no CRM, em outra aba.
const props = defineProps({
  seguro: { type: Object, default: null },
  demo: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  // De onde vêm os ajustes das renovações (o WhatsApp escolhido).
  fonteDasRenovacoes: { type: Object, default: () => renovacoesFonteReal() },
});
const emit = defineEmits(['confirmar']);

const { t } = useI18n();
const tc = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.COTACAO.CONFIRMAR.${chave}`, valores);
const dialogo = useTemplateRef('dialogo');
const caixa = ref('');

const textos = useTextosDoSeguro();

const nome = computed(() => props.seguro?.pessoa?.name || '');
const cotacao = computed(() => props.seguro?.cotacao ?? {});
const aviso = computed(() => {
  const { premioCentavos, seguradora } = cotacao.value;
  const chave = [
    'PARA',
    caixa.value ? '' : 'SEM_CAIXA',
    seguradora ? '' : 'SEM_SEGURADORA',
  ]
    .filter(Boolean)
    .join('_');
  return tc(chave, {
    nome: nome.value,
    caixa: caixa.value,
    seguradora,
    valor: textos.valor(emReais(premioCentavos ?? 0)),
  });
});
const cardId = computed(() => props.seguro?.renovacao?.cardId ?? null);

const lerCaixa = async () => {
  if (props.demo) return;
  try {
    const { caixas, ajustes } = await props.fonteDasRenovacoes.ajustes();
    caixa.value = nomeDaCaixaNaFrase(
      caixaEscolhida(caixas, ajustes?.caixaId)?.nome ?? ''
    );
  } catch {
    caixa.value = '';
  }
};

defineExpose({
  // Espera o nome do WhatsApp e só então abre.
  abrir: async () => {
    caixa.value = '';
    await lerCaixa();
    dialogo.value?.abrir();
  },
  fechar: () => dialogo.value?.fechar(),
});
</script>

<template>
  <DialogoDeConfirmacao
    ref="dialogo"
    marca="confirmar-proposta"
    tipo="edit"
    :titulo="tc('TITULO')"
    :aviso="aviso"
    aviso-forte
    :confirmar="tc('ENVIAR')"
    :voltar="tc('VOLTAR')"
    :ocupado="ocupado"
    @confirmar="emit('confirmar')"
  >
    <router-link
      v-if="cardId"
      :to="destinoDoCard(cardId, demo)"
      target="_blank"
      rel="noopener noreferrer"
      data-carteira="ver-pdf-da-proposta"
      class="inline-flex items-center self-start gap-1 text-sm font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      <span class="size-4 i-lucide-file-text" aria-hidden="true" />
      {{ tc('VER_PDF') }}
      <span class="size-4 i-lucide-external-link" aria-hidden="true" />
    </router-link>
  </DialogoDeConfirmacao>
</template>
