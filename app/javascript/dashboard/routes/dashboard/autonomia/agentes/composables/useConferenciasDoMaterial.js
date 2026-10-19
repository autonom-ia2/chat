import { getCurrentInstance, onBeforeUnmount, ref } from 'vue';
import MaterialAPI from 'dashboard/api/autonomia/material';

// #1426 (tema 4b) — o que as conferências e o autoteste acharam no material do agente (Fase 2): os problemas, um por
// vez, e o resumo do autoteste. A lista de materiais segue na store autonomiaSources; a página relê isto quando a lista
// muda (um material terminou a revisão, entrou ou saiu), e aqui a releitura se repete sozinha enquanto o autoteste
// roda. É ela que faz o resultado e os cartões novos aparecerem sem recarregar.
export const RELEITURA_DO_AUTOTESTE_MS = 3000;
// A base mudou: as contradições e a rodada automática só começam 2 min depois (BaseMudouJob::ESPERA). Uma releitura a
// mais, com folga, mostra o "rodando" e o que elas acharem sem recarregar.
export const RELEITURA_DEPOIS_DA_BASE_MS = 150000;

const doAutoteste = salvo =>
  salvo
    ? {
        estado: salvo.estado,
        quando: salvo.quando,
        feitas: salvo.feitas || 0,
        total: salvo.total || 0,
        doMaterial: salvo.do_material || 0,
        deFora: salvo.de_fora || 0,
        certasDoMaterial: salvo.certas_do_material || 0,
        certasDeFora: salvo.certas_de_fora || 0,
        resultados: salvo.resultados || [],
      }
    : null;

export function useConferenciasDoMaterial({ agentId, api = MaterialAPI }) {
  const problemas = ref([]);
  const autoteste = ref(null);
  const lido = ref(false);
  const erro = ref(false);
  let relogio = null;
  let relogioDaBase = null;
  let parado = false;

  const aplicar = ({ data } = {}) => {
    problemas.value = data?.problemas || [];
    autoteste.value = doAutoteste(data?.autoteste);
    lido.value = true;
  };

  const pararReleitura = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  // Quem relê é passado de fora (`aoReler`): a releitura agenda a próxima sem se referir a si.
  const agendar = aoReler => {
    pararReleitura();
    if (parado || autoteste.value?.estado !== 'rodando') return;
    relogio = setTimeout(aoReler, RELEITURA_DO_AUTOTESTE_MS);
  };

  const ler = async () => {
    try {
      aplicar(await api.get(agentId()));
      erro.value = false;
    } catch {
      erro.value = true;
    }
    agendar(ler);
  };

  const lerDepoisDaMudanca = () => {
    clearTimeout(relogioDaBase);
    ler();
    if (!parado) relogioDaBase = setTimeout(ler, RELEITURA_DEPOIS_DA_BASE_MS);
  };

  // As ações levantam o erro para quem chamou mostrar ao lado do botão.
  const agir = async acao => {
    aplicar(await acao());
    agendar(ler);
  };

  const resolver = (problemaId, escolha) =>
    agir(() => api.resolver(agentId(), problemaId, escolha));
  const pedirAutoteste = () => agir(() => api.pedirAutoteste(agentId()));

  const parar = () => {
    parado = true;
    pararReleitura();
    clearTimeout(relogioDaBase);
  };

  if (getCurrentInstance()) onBeforeUnmount(parar);

  return {
    problemas,
    autoteste,
    lido,
    erro,
    ler,
    lerDepoisDaMudanca,
    resolver,
    pedirAutoteste,
    parar,
  };
}
