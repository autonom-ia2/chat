import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

// #2694 — F2, "Com quem fica" de verdade. Quem gere funis (permissoes.trocarDono)
// escolhe uma das pessoas que enxergam o funil escolhido; a lista vem do
// servidor e é refeita quando o funil muda. Se a pessoa escolhida não tem o
// funil novo, a escolha volta para "você" e a tela avisa. O agente comum fica
// com "você", sem lista. Saiu de AcharConfiraPage.vue pela trava de tamanho.
export const VOCE = 'voce';

// A recusa do servidor ao dono escolhido (leads/crm_cards), pelo código.
const ERRO_DO_CODIGO = {
  'prospecting.crm_send.owner_forbidden': 'dono_sem_chave',
  'prospecting.crm_send.owner_not_allowed': 'dono_sem_funil',
};

// A frase de cada erro do envio ao funil (folha e gaveta).
// Quantas empresas cabem num Público de uma vez: o mesmo teto do servidor
// (AudienceFromLeads::MAX_LEADS, medido no #2695 r1).
export const LIMITE_DO_PUBLICO = 100;

export const TEXTO_DO_ERRO = {
  funil: 'PROSPECTING_ACHAR.FOLHA.ERRO_FUNIL',
  lista: 'PROSPECTING_ACHAR.FOLHA.ERRO_LISTA',
  lista_ninguem: 'PROSPECTING_ACHAR.FOLHA.ERRO_LISTA_NINGUEM',
  lista_demais: 'PROSPECTING_ACHAR.FOLHA.ERRO_LISTA_DEMAIS',
  lista_contato_apagado: 'PROSPECTING_ACHAR.FOLHA.ERRO_LISTA_CONTATO_APAGADO',
  dono_sem_chave: 'PROSPECTING_ACHAR.FOLHA.ERRO_DONO_SEM_CHAVE',
  dono_sem_funil: 'PROSPECTING_ACHAR.FOLHA.ERRO_DONO_SEM_FUNIL',
};

// O erro da tela quando nada entrou porque o servidor recusou o dono; senão nulo.
export const erroDoDono = resumo => {
  const recusa = resumo.failed.find(item => ERRO_DO_CODIGO[item.codigo]);
  return recusa ? ERRO_DO_CODIGO[recusa.codigo] : null;
};

export function useDonoDaLista({ fonte, permissoes, destino }) {
  const { t } = useI18n();
  const pessoas = ref([]);
  const pessoaId = ref(VOCE);

  const nomeDe = id =>
    pessoas.value.find(pessoa => pessoa.id === id)?.nome ||
    t('PROSPECTING_ACHAR.COMUM.VOCE');
  const pessoaNome = computed(() =>
    pessoaId.value === VOCE
      ? t('PROSPECTING_ACHAR.COMUM.VOCE')
      : nomeDe(pessoaId.value)
  );
  // O que vai ao servidor: nada quando fica com quem manda.
  const donoId = computed(() =>
    pessoaId.value === VOCE ? null : pessoaId.value
  );

  const funilDoPedido = () =>
    permissoes.value.trocarDono ? destino.value?.funil.id || null : null;

  // Troca de funil rápida: a resposta de um funil que já não é o escolhido é
  // descartada. A escolha é lida depois da resposta (a pessoa pode ter mudado).
  const carregarPessoas = async () => {
    const funilId = funilDoPedido();
    let lista = null;
    try {
      lista = await fonte.value.pessoas({ funilId });
    } catch {
      // Sem a lista, fica "você": o servidor confere de novo ao mandar.
    }
    if (funilDoPedido() !== funilId) return;
    const antes = { id: pessoaId.value, nome: pessoaNome.value };
    pessoas.value = lista || [];
    if (antes.id === VOCE) return;
    if (lista?.some(pessoa => pessoa.id === antes.id)) return;
    pessoaId.value = VOCE;
    const frase = lista ? 'SEM_O_FUNIL' : 'ERRO_LISTA';
    useAlert(t(`PROSPECTING_ACHAR.COM_QUEM_PAINEL.${frase}`, antes));
  };

  watch(
    () => destino.value?.funil.id,
    (novo, antigo) => {
      if (novo !== antigo) carregarPessoas();
    }
  );

  return { pessoas, pessoaId, pessoaNome, donoId, carregarPessoas };
}
