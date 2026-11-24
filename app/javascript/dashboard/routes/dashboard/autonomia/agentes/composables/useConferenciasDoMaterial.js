import { getCurrentInstance, onBeforeUnmount, ref } from 'vue';
import MaterialAPI from 'dashboard/api/autonomia/material';

// #1426 (tema 4b) — o que as conferências acharam no material do agente (Fase 2): os problemas, um por vez. A lista de
// materiais segue na store autonomiaSources; a página relê isto quando a lista muda (um material terminou a revisão,
// entrou ou saiu).
// A base mudou: as contradições só começam 2 min depois (BaseMudouJob::ESPERA). Uma releitura a mais, com folga, mostra
// o que elas acharem sem recarregar.
export const RELEITURA_DEPOIS_DA_BASE_MS = 150000;

export function useConferenciasDoMaterial({ agentId, api = MaterialAPI }) {
  const problemas = ref([]);
  const lido = ref(false);
  const erro = ref(false);
  let relogioDaBase = null;
  let parado = false;

  const aplicar = ({ data } = {}) => {
    problemas.value = data?.problemas || [];
    lido.value = true;
  };

  const ler = async () => {
    try {
      aplicar(await api.get(agentId()));
      erro.value = false;
    } catch {
      erro.value = true;
    }
  };

  const lerDepoisDaMudanca = () => {
    clearTimeout(relogioDaBase);
    ler();
    if (!parado) relogioDaBase = setTimeout(ler, RELEITURA_DEPOIS_DA_BASE_MS);
  };

  // A ação levanta o erro para quem chamou mostrar ao lado do botão.
  const resolver = async (problemaId, escolha) =>
    aplicar(await api.resolver(agentId(), problemaId, escolha));

  const parar = () => {
    parado = true;
    clearTimeout(relogioDaBase);
  };

  if (getCurrentInstance()) onBeforeUnmount(parar);

  return { problemas, lido, erro, ler, lerDepoisDaMudanca, resolver, parar };
}
