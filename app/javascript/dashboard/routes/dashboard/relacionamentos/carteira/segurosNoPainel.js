// #2897 — os seguros de quem está na conversa, no painel do contato. Este é o
// único pedaço da carteira que o painel de conversas carrega em toda conta: a
// pergunta "aqui aparecem os seguros?" e o endereço da peça. A peça em si
// (components/carteira/PainelDeSeguros.vue, com a gaveta do seguro) só é
// baixada quando a resposta é sim: chega por import dinâmico.
//
// Aparecem quando a conta tem a carteira (o payload dela diz `carteira_seguros`;
// quem decide é Carteira::Acesso, no servidor) e quem atende pode ver contatos.
// Função personalizada sem `contact_view` não vê seguro nenhum, nem o do
// contato de uma conversa que ela enxerga: o servidor responde 401 nessa
// leitura, então a tela nem monta a peça nem chama a rota.
import { computed, defineAsyncComponent } from 'vue';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import { useContaDeSeguros } from './useContaDeSeguros';

const PainelDeSeguros = defineAsyncComponent(
  () => import('../components/carteira/PainelDeSeguros.vue')
);

export const useSegurosNoPainel = () => {
  const contaDeSeguros = useContaDeSeguros();
  const { canViewRelationshipRecords } = useRelationshipPermissions();
  const comSeguros = computed(
    () => contaDeSeguros.value && canViewRelationshipRecords.value
  );

  return { PainelDeSeguros, comSeguros };
};

// A gaveta do seguro abre por cima do painel, mas mora no <body>: para quem
// fecha o painel "ao clicar fora" (ConversationSidebar, em tela estreita), um
// toque nela seria um toque fora, e fechar o painel desmontaria a gaveta com a
// pessoa lendo. A marca é a da própria gaveta (GavetaDoSeguro.vue); sem a
// carteira ela nunca existe na tela e a resposta é sempre "não".
const GAVETA_DO_SEGURO = '[data-relacionamentos="gaveta-do-seguro"]';

export const gavetaDoSeguroAberta = (documento = document) =>
  Boolean(documento.querySelector(GAVETA_DO_SEGURO));
