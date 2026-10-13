import { computed } from 'vue';

// #1423 — como o card chama o cliente: o nome curto (pessoa, senão empresa),
// o título do topo (empresa > pessoa > negócio) e a frase de baixo (a pessoa
// e o negócio, só quando não repetem o título).
export const useCardNomes = ({ t, card }) => {
  const nomeEmpresa = computed(() =>
    String(card.value.company?.name || '').trim()
  );
  const nomeContato = computed(() =>
    String(
      card.value.contact?.name || card.value.contact?.phone_number || ''
    ).trim()
  );
  const nomeNegocio = computed(() => String(card.value.title || '').trim());
  const nome = computed(
    () => nomeContato.value || nomeEmpresa.value || t('CRM_CARD.O_CLIENTE')
  );
  const titulo = computed(
    () =>
      nomeEmpresa.value ||
      nomeContato.value ||
      nomeNegocio.value ||
      t('CRM_KANBAN.RELATIONSHIP.OPPORTUNITY_DETAILS')
  );
  const subtitulo = computed(() => {
    const partes = [];
    if (
      nomeEmpresa.value &&
      nomeContato.value &&
      nomeEmpresa.value !== nomeContato.value
    )
      partes.push(nomeContato.value);
    if (
      nomeNegocio.value &&
      ![nomeEmpresa.value, nomeContato.value, titulo.value].includes(
        nomeNegocio.value
      )
    )
      partes.push(
        t('CRM_CARD.RESUMO.NEGOCIO_DE', { titulo: nomeNegocio.value })
      );
    return partes.join(' · ') || t('CRM_CARD.RESUMO.TEXTO');
  });
  return { nome, titulo, subtitulo };
};
