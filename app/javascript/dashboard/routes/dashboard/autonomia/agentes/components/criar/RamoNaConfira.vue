<script setup>
import { computed } from 'vue';
import ProntoDoRamo from './ProntoDoRamo.vue';
import FerramentasDoRamo from './FerramentasDoRamo.vue';
import VitrineJaVem from '../../vitrine/components/VitrineJaVem.vue';

// #2881 — o bloco do agente pronto por ramo no Confira da página "Criar agente" (AgenteCriarPage), fora dela para a
// página não crescer. Toma o lugar do "Já vem com estas ferramentas" (VitrineJaVem) quando a conversa tem modelo.
// `ramo` é o useModeloDeRamo da página (as listas do servidor e o `mudar`); `prontas` é o useProntasDoConstrutor
// dela: só aparece a ferramenta que o "Começar" vai mesmo incluir (a conta liberou e o agente ainda não tem).
// Mexer nas ferramentas (tirar, incluir, alterar a frase) pede a chave "Ferramentas dos agentes", a mesma do
// "Incluir" da vitrine (`prontas.podeIncluir`); o servidor recusa sem ela. Quem não tem a chave vê as ferramentas e a
// frase "Use quando" de cada uma, sem botões, e o aviso de sempre: o agente começa sem elas. Perguntas e documentos
// só pedem a permissão da página (`podeMudar`).
const props = defineProps({
  ramo: { type: Object, required: true },
  prontas: { type: Object, required: true },
  nome: { type: String, required: true },
  podeMudar: { type: Boolean, default: false },
  linkDaVitrine: { type: String, default: '' },
});

const soAs = (itens, chaves) =>
  itens.filter(item => chaves.includes(item.fonte));

const podeIncluir = computed(() => props.prontas.podeIncluir.value);
const semPermissao = computed(() => props.prontas.semPermissao.value);
// As que entram no "Começar". Sem a chave nenhuma entra: a lista é só para ler.
const entram = computed(() =>
  soAs(props.ramo.ferramentas.value, props.prontas.visiveis.value)
);
const ferramentas = computed(() =>
  podeIncluir.value
    ? entram.value
    : soAs(props.ramo.ferramentas.value, props.prontas.escolhidas.value)
);
const tambem = computed(() =>
  soAs(props.ramo.tambem.value, props.prontas.combinaTambem.value)
);
// A lista que sai do FerramentasDoRamo só tem as ferramentas que ele mostra, e o servidor troca a lista inteira. As
// que a tela não mostra (o agente já tem, ou esta tela não conhece) continuam na lista, no lugar em que estavam: não
// é por não aparecerem aqui que saem do agente pronto. `aoGravar`: o aviso de "gravou" do campo da frase, quando há.
const mudarFerramentas = (nova, aoGravar) => {
  const mostradas = ferramentas.value.map(item => item.fonte);
  const todas =
    props.ramo.modelo?.value?.ferramentas || props.ramo.ferramentas.value;
  const mantidas = todas.flatMap(item => {
    if (!mostradas.includes(item.fonte)) return [item];
    const mudada = nova.find(outra => outra.fonte === item.fonte);
    return mudada ? [mudada] : [];
  });
  const jaNaLista = mantidas.map(item => item.fonte);
  props.ramo.mudar(
    'ferramentas',
    [...mantidas, ...nova.filter(item => !jaNaLista.includes(item.fonte))],
    aoGravar
  );
};
const link = computed(() => (podeIncluir.value ? props.linkDaVitrine : ''));
const pagas = computed(() => (link.value ? props.ramo.pagas.value : []));
// Sem nada para mostrar (a conta não tem as ferramentas prontas), a linha das ferramentas nem aparece.
const quantas = computed(() => {
  const algo =
    ferramentas.value.length + tambem.value.length + pagas.value.length > 0;
  return algo ? entram.value.length : null;
});
</script>

<template>
  <ProntoDoRamo
    :nome="nome"
    :perguntas="ramo.perguntas.value"
    :documentos="ramo.documentos.value"
    :ferramentas="quantas"
    :pode-mudar="podeMudar"
    :gravando="ramo.gravando.value"
    @mudar="ramo.mudar($event.lista, $event.itens, $event.aoGravar)"
  >
    <template #ferramentas>
      <VitrineJaVem
        v-if="semPermissao"
        :nome="nome"
        :ids="prontas.escolhidas.value"
        sem-permissao
      />
      <FerramentasDoRamo
        :nome="nome"
        :ferramentas="ferramentas"
        :tambem="tambem"
        :pagas="pagas"
        :link-da-vitrine="link"
        :pode-mudar="podeMudar && podeIncluir"
        :gravando="ramo.gravando.value.ferramentas === true"
        @mudar="mudarFerramentas"
      />
    </template>
  </ProntoDoRamo>
</template>
