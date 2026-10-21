import { computed, ref, toValue } from 'vue';
import BaseDoAgenteAPI from 'dashboard/api/autonomia/baseDoAgente';

// #1429 F3 — a base de seguros do agente na página dele: a leitura (com que base trabalha e se há uma nova),
// atualizar e desfazer. Só a base muda: instrução, jeito de falar, material e ferramentas ficam como estão (o servidor
// garante). Sem a leitura, a linha some: ela informa, não é um dado de que a página dependa.
export const ESTADO_BASE = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
};

export function useBaseDoAgente(agentId) {
  const estado = ref(ESTADO_BASE.CARREGANDO);
  const base = ref(null);
  const desfazendo = ref(false);
  const erroDesfazer = ref(false);
  const textoErroDesfazer = ref('');

  const id = () => Number(toValue(agentId));

  const carregar = async () => {
    estado.value = ESTADO_BASE.CARREGANDO;
    try {
      const { data } = await BaseDoAgenteAPI.ler(id());
      base.value = data;
      estado.value = ESTADO_BASE.PRONTO;
    } catch {
      estado.value = ESTADO_BASE.ERRO;
    }
  };

  // Relê sem tirar a linha da tela (depois de outra gaveta, do Mudar conversando ou de um Desfazer recusado). Falhou, fica
  // o que está.
  const recarregar = async () => {
    try {
      const { data } = await BaseDoAgenteAPI.ler(id());
      base.value = data;
      estado.value = ESTADO_BASE.PRONTO;
    } catch {
      // a linha segue como estava
    }
  };

  // A linha aparece quando o servidor manda uma situação (nula: conta geral com agente sem base).
  const temOQueMostrar = computed(
    () => estado.value === ESTADO_BASE.PRONTO && Boolean(base.value?.situacao)
  );

  // -> { versao, perguntas }: `versao` é a da base nova comparada, a que o "atualizar" manda.
  const comparar = async signal => {
    const { data } = await BaseDoAgenteAPI.comparar(id(), signal);
    return { versao: data?.versao, perguntas: data?.perguntas || [] };
  };

  // Quem chama trata o erro (a gaveta mostra o motivo no lugar). A linha é relida: se a base nova mudou (409) ou não
  // existe mais (422), ela passa a mostrar o que vale agora.
  const atualizar = async versao => {
    try {
      const { data } = await BaseDoAgenteAPI.atualizar(id(), versao);
      base.value = data;
      erroDesfazer.value = false;
      textoErroDesfazer.value = '';
    } catch (erro) {
      recarregar();
      throw erro;
    }
  };

  // O Desfazer que não vale mais (409: o agente mudou depois) traz o motivo do servidor; a linha mostra ele, sem
  // sugerir tentar de novo. Outra falha: o aviso genérico da linha.
  const desfazer = async () => {
    desfazendo.value = true;
    erroDesfazer.value = false;
    textoErroDesfazer.value = '';
    try {
      const { data } = await BaseDoAgenteAPI.desfazer(id());
      base.value = data;
      return true;
    } catch (erro) {
      erroDesfazer.value = true;
      textoErroDesfazer.value =
        erro?.response?.status === 409 ? erro.response.data?.error || '' : '';
      recarregar();
      return false;
    } finally {
      desfazendo.value = false;
    }
  };

  return {
    estado,
    base,
    temOQueMostrar,
    desfazendo,
    erroDesfazer,
    textoErroDesfazer,
    carregar,
    recarregar,
    comparar,
    atualizar,
    desfazer,
  };
}
