import { computed, reactive } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #1479 (opção A do Rodrigo, 01/11) — "Endereço do atendimento" e "Telefone de contato" do agente, ao lado das
// instruções. O agente manda o endereço como mapa (`enviar_localizacao`) e o telefone como cartão de contato
// (`enviar_contato`), e os dois entram na instrução. Vazio: vale o da página de agendamento, como hoje.
// Só com a flag `agentes_enviar_local_e_contato` (ext_2, posição 21).
//
// PROTÓTIPO — ADAPTADOR FALSO. Ainda não há backend: os valores ficam neste módulo (e no localStorage do navegador,
// para sobreviver ao F5 da demo). A interface já é a do backend que vem depois:
//   ler:    agente.config.atendimento = { endereco, telefone }   (telefone em E.164, ou vazio)
//   salvar: store.dispatch('autonomiaAgents/update', { id, config: { atendimento: { endereco, telefone } } })
// Trocar `lerLocal`/`gravarLocal` por isso é a única mudança quando o endpoint existir.

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

const VAZIO = Object.freeze({ endereco: '', telefone: '' });
const CHAVE = id => `prototipo-1479-atendimento-${id}`;
const locais = reactive({});

const normalizar = dados =>
  Object.freeze({
    endereco: String(dados?.endereco || '').trim(),
    telefone: String(dados?.telefone || ''),
  });

const lerLocal = id => {
  if (locais[id]) return locais[id];
  try {
    const salvo = window.localStorage.getItem(CHAVE(id));
    if (salvo) locais[id] = normalizar(JSON.parse(salvo));
  } catch {
    // Navegador sem storage: fica só na memória da página.
  }
  return locais[id] || null;
};

const gravarLocal = (id, dados) => {
  locais[id] = dados;
  try {
    window.localStorage.setItem(CHAVE(id), JSON.stringify(dados));
  } catch {
    // Sem storage: vale o que está na memória.
  }
};

// O que vier do servidor (agente.config.atendimento) vence; enquanto não vem, o adaptador falso.
export const lerAtendimento = agente => {
  if (!agente?.id) return VAZIO;
  const doServidor = agente.config?.atendimento;
  if (doServidor) return normalizar(doServidor);
  return lerLocal(agente.id) || VAZIO;
};

export const salvarAtendimento = async (agente, dados) => {
  gravarLocal(agente.id, normalizar(dados));
};

export const temAtendimento = dados =>
  Boolean(dados?.endereco || dados?.telefone);
