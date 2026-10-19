import { computed, getCurrentInstance, onBeforeUnmount, ref } from 'vue';
import { criarFonteDoMaterial } from '../prototipo/fonteMaterial';
import { ESTADO_MATERIAL, estadoDoMaterial } from '../utils/estadoDoMaterial';

// #1426 (tema 4) — o material do agente com estado real: lê a base, as conferências e o autoteste,
// e se relê sozinho enquanto algo está em andamento (lendo, revisando ou autoteste rodando). É essa
// releitura que faz a reprovação aparecer sem recarregar: hoje a store para de reler quando a leitura
// termina, antes da revisão. Sem nada em andamento, para.
// `fonte` é o adaptador (prototipo/fonteMaterial.js); o spec passa o dele.
export const RELEITURA_MS = 1000;

const EM_ANDAMENTO = [ESTADO_MATERIAL.LENDO, ESTADO_MATERIAL.REVISANDO];

export function useMaterialDoAgente({ fonte = criarFonteDoMaterial() } = {}) {
  const fontes = ref([]);
  const problemas = ref([]);
  const autoteste = ref(null);
  const lido = ref(false);
  const erro = ref(false);
  let relogio = null;
  let parado = false;

  const estadoDe = item => estadoDoMaterial(item, problemas.value);

  const emAndamento = computed(
    () =>
      fontes.value.some(item => EM_ANDAMENTO.includes(estadoDe(item))) ||
      autoteste.value?.estado === 'rodando'
  );

  const aplicar = retrato => {
    fontes.value = retrato?.fontes || [];
    problemas.value = retrato?.problemas || [];
    autoteste.value = retrato?.autoteste || null;
    lido.value = true;
  };

  const pararReleitura = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  // Quem relê é passado de fora (`aoReler`): a releitura agenda a próxima sem se referir a si.
  const agendar = aoReler => {
    pararReleitura();
    if (parado || !emAndamento.value) return;
    relogio = setTimeout(aoReler, RELEITURA_MS);
  };

  const ler = async () => {
    erro.value = false;
    try {
      aplicar(await fonte.ler());
    } catch {
      erro.value = true;
    }
    agendar(ler);
  };

  const agir = async acao => {
    aplicar(await acao());
    agendar(ler);
  };

  const enviar = descritor => agir(() => fonte.enviar(descritor));
  const tirar = fonteId => agir(() => fonte.tirar(fonteId));
  const resolver = (problemaId, escolha) =>
    agir(() => fonte.resolver(problemaId, escolha));
  const pedirAutoteste = () => agir(() => fonte.pedirAutoteste());

  const parar = () => {
    parado = true;
    pararReleitura();
  };

  if (getCurrentInstance()) onBeforeUnmount(parar);

  return {
    fontes,
    problemas,
    autoteste,
    lido,
    erro,
    emAndamento,
    estadoDe,
    ler,
    enviar,
    tirar,
    resolver,
    pedirAutoteste,
    testar: payload => fonte.testar(payload),
    parar,
  };
}
