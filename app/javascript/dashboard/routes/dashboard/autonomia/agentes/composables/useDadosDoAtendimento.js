import { computed, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import { generateMutationTypes } from 'dashboard/store/storeFactory';
import { mensagemDaRecusa } from './useComecarAAtender';

// #1479 (opção B do Rodrigo, 01/11) / #2723 — "Endereço do atendimento" e "Telefone de contato" do agente, num bloco
// próprio da página ("Endereço e telefone"), nos dois modos (manual e conversando). Só com a flag
// `agentes_enviar_local_e_contato`.
//   ler:    agente.config.atendimento = { endereco, telefone }   (telefone em E.164, ou vazio)
//   salvar: PATCH do agente com { config: { atendimento } }; o servidor mescla com o resto do config e confere o
//           telefone (422 com a explicação quando não é válido).
// O agente diz o endereço por escrito (não manda mapa dele) e manda o telefone como cartão de contato.

// Mesmo teto do servidor (Autonomia::Agents::DadosDoAtendimento::MAX_ENDERECO).
export const MAX_ENDERECO = 300;

export const dadosDoAtendimentoLigado = conta =>
  conta?.features?.[FEATURE_FLAGS.AGENTES_ENVIAR_LOCAL_E_CONTATO] === true;

export function useDadosDoAtendimentoLigado() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  // Mesma leitura do useFase2: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      dadosDoAtendimentoLigado(conta.value(contaId.value))
  );
}

const normalizar = dados =>
  Object.freeze({
    endereco: String(dados?.endereco || '').trim(),
    telefone: String(dados?.telefone || ''),
  });

export const lerAtendimento = agente => normalizar(agente?.config?.atendimento);

export const temAtendimento = dados =>
  Boolean(dados?.endereco || dados?.telefone);

const { UPSERT } = generateMutationTypes('AutonomiaAgents');

// Salva pelo servidor e põe o agente devolvido na lista do painel (a página relê dele). O erro sobe para quem chama:
// `recusa(erro)` é a explicação do servidor quando ele recusou (422), ou null.
export function useSalvarAtendimento() {
  const store = useStore();
  const salvando = ref(false);

  const salvar = async (agente, dados) => {
    salvando.value = true;
    try {
      const { data } = await AutonomiaAgentsAPI.update(agente.id, {
        config: { atendimento: { ...normalizar(dados) } },
      });
      store.commit(`autonomiaAgents/${UPSERT}`, data);
      return data;
    } finally {
      salvando.value = false;
    }
  };

  return { salvando, salvar, recusa: mensagemDaRecusa };
}
