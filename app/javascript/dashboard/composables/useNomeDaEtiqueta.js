import {
  computed,
  effectScope,
  getCurrentInstance,
  ref,
  shallowRef,
  watch,
} from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import EtiquetasDoCelularAPI from 'dashboard/api/etiquetasDoCelular';
import {
  mesmoNome,
  nomeDaEtiqueta,
  tituloTecnicoDoNome,
} from 'dashboard/helper/nomeDaEtiqueta';

// Nome livre das etiquetas (#1823, F1a), atrás da flag `etiquetas_do_whatsapp`.
// Uma carga por conta para todos os chips da tela; quem cria ou edita atualiza o
// cache na hora. Os outros atendentes veem o nome novo ao recarregar o painel ou
// ao reabrir Configurações › Etiquetas (`recarregar`). Sem websocket.
// Falha na carga não entra no cache: a conta fica sem chave e a próxima carga
// (Configurações › Etiquetas, troca de conta ou de flag) tenta de novo.
const nomesPorConta = ref({});
const pedidos = new Map();
// Nomes gravados aqui enquanto a lista da conta carrega: a lista que chega
// depois é mais velha que eles, então eles ficam por cima dela.
const gravadosDuranteACarga = new Map();

const comNomes = (accountId, nomes) => {
  nomesPorConta.value = { ...nomesPorConta.value, [accountId]: nomes };
};

const carregar = (accountId, { forcar = false } = {}) => {
  if (!accountId) return Promise.resolve();
  if (pedidos.has(accountId)) return pedidos.get(accountId);
  if (!forcar && nomesPorConta.value[accountId]) return Promise.resolve();

  const gravados = new Map();
  gravadosDuranteACarga.set(accountId, gravados);
  const pedido = NomesDeEtiquetasAPI.listar()
    .then(({ data }) => {
      const lista = (data?.payload || []).map(({ label_id: id, nome }) => [
        id,
        nome,
      ]);
      comNomes(accountId, Object.fromEntries([...lista, ...gravados]));
    })
    .catch(error => {
      // Falhou: a tela segue com o que já tinha (ou o nome derivado do título).
      // eslint-disable-next-line no-console
      console.error('Nomes das etiquetas: falha ao carregar', error);
    })
    .finally(() => {
      pedidos.delete(accountId);
      gravadosDuranteACarga.delete(accountId);
    });
  pedidos.set(accountId, pedido);
  return pedido;
};

// Etiquetas do WhatsApp do celular (#1823, F1b), atrás da flag própria
// `etiquetas_do_celular`: por conta, as correspondências de cada etiqueta daqui
// (uma por caixa em que ela existe no celular). Mesma carga única por conta.
const vinculosPorConta = ref({});
const pedidosDeVinculos = new Map();

// Agrupa em uma passada: { [label_id]: [vínculo, …] }.
const agruparPorEtiqueta = lista => {
  const porEtiqueta = {};
  lista.forEach(item => {
    const vinculo = {
      caixa: item.caixa,
      inboxId: item.inbox_id,
      nomeNoCelular: item.nome_no_celular,
      criadaPeloCelular: item.criada_pelo_celular,
    };
    (porEtiqueta[item.label_id] ||= []).push(vinculo);
  });
  return porEtiqueta;
};

const carregarVinculos = (accountId, { forcar = false } = {}) => {
  if (!accountId) return Promise.resolve();
  if (pedidosDeVinculos.has(accountId)) {
    return pedidosDeVinculos.get(accountId);
  }
  if (!forcar && vinculosPorConta.value[accountId]) return Promise.resolve();

  const pedido = EtiquetasDoCelularAPI.listar()
    .then(({ data }) => {
      vinculosPorConta.value = {
        ...vinculosPorConta.value,
        [accountId]: agruparPorEtiqueta(data?.payload || []),
      };
    })
    .catch(error => {
      // Falhou: sem selo do WhatsApp até a próxima carga, que tenta de novo.
      // eslint-disable-next-line no-console
      console.error('Etiquetas do celular: falha ao carregar', error);
    })
    .finally(() => pedidosDeVinculos.delete(accountId));
  pedidosDeVinculos.set(accountId, pedido);
  return pedido;
};

const SEM_VINCULOS = Object.freeze([]);

// Estado único do módulo, para todos os chips da tela: as flags, o mapa título →
// id e os dois watches que disparam as cargas existem uma vez só (singleton), não
// um por chip. Com as flags desligadas, nenhum watch carrega nada.
// A store vem da instância que usa o composable, lida com cuidado (como no
// useHorarioUnicoCaixa): sem a store do painel, as flags contam como desligadas.
const storeAtual = shallowRef(null);
const getter = nome => storeAtual.value?.getters?.[nome];
let estado = null;

const criarEstado = () => {
  const accountId = computed(() => getter('getCurrentAccountId'));
  const flagLigada = flag =>
    Boolean(
      accountId.value &&
        getter('accounts/isFeatureEnabledonAccount')?.(accountId.value, flag)
    );
  const ligada = computed(() =>
    flagLigada(FEATURE_FLAGS.ETIQUETAS_DO_WHATSAPP)
  );
  const celularLigado = computed(() =>
    flagLigada(FEATURE_FLAGS.ETIQUETAS_DO_CELULAR)
  );
  // Só o que é etiqueta da conta ganha nome: `Label.vue` e o chip antigo também
  // mostram texto que não é etiqueta (SLA, Linear) e esse fica como está.
  const idPorTitulo = computed(
    () =>
      new Map(
        (getter('labels/getLabels') || []).map(({ id, title }) => [title, id])
      )
  );

  watch(
    [ligada, accountId],
    ([estaLigada, conta]) => {
      if (estaLigada) carregar(conta);
    },
    { immediate: true }
  );
  watch(
    [celularLigado, accountId],
    ([estaLigado, conta]) => {
      if (estaLigado) carregarVinculos(conta);
    },
    { immediate: true }
  );
  return { accountId, ligada, celularLigado, idPorTitulo };
};

const estadoCompartilhado = () => {
  estado ||= effectScope(true).run(criarEstado);
  return estado;
};

export function useNomeDaEtiqueta() {
  // Chamado fora de um componente (ou sem a store): não troca a store dos outros.
  const store = getCurrentInstance()?.proxy?.$store;
  if (store && storeAtual.value !== store) storeAtual.value = store;
  const { accountId, ligada, celularLigado, idPorTitulo } =
    estadoCompartilhado();
  const nomesDaConta = computed(
    () => nomesPorConta.value[accountId.value] || {}
  );

  // Onde a etiqueta existe no celular (uma entrada por caixa). Sem a flag
  // `etiquetas_do_celular`, ou etiqueta só daqui: lista vazia.
  const vinculosDe = titulo => {
    if (!celularLigado.value || !idPorTitulo.value.has(titulo)) {
      return SEM_VINCULOS;
    }
    const daConta = vinculosPorConta.value[accountId.value] || {};
    return daConta[idPorTitulo.value.get(titulo)] || SEM_VINCULOS;
  };

  const nomeDe = titulo => {
    if (!ligada.value || !idPorTitulo.value.has(titulo)) return titulo;
    const nomeGuardado = nomesDaConta.value[idPorTitulo.value.get(titulo)];
    const nomeNoCelular = vinculosDe(titulo)[0]?.nomeNoCelular;
    return nomeDaEtiqueta(titulo, { nomeGuardado, nomeNoCelular });
  };

  // A conta é a do momento do pedido: trocar de conta durante a gravação não
  // põe o nome no cache da outra.
  const guardarNome = async (labelId, nome) => {
    const conta = accountId.value;
    const { data } = await NomesDeEtiquetasAPI.gravar(labelId, nome);
    gravadosDuranteACarga.get(conta)?.set(labelId, data.payload.nome);
    comNomes(conta, {
      ...(nomesPorConta.value[conta] || {}),
      [labelId]: data.payload.nome,
    });
  };

  const recarregar = () =>
    Promise.all([
      ligada.value ? carregar(accountId.value, { forcar: true }) : null,
      celularLigado.value
        ? carregarVinculos(accountId.value, { forcar: true })
        : null,
    ]);

  // Busca pelo título técnico e pelo nome exibido ("aguardando_retorno",
  // "aguardando retorno" ou "cliente vip"). Flag desligada: a busca de sempre.
  // Duas buscas somadas, não uma chave a mais: o picoSearch tira a média das
  // chaves, e o nome que não bate puxaria para baixo o título que bate.
  const buscar = (lista, termo, chaves = ['title']) => {
    const pelasChaves = picoSearch(lista, termo, chaves);
    if (!ligada.value) return pelasChaves;
    const comNome = lista.map(etiqueta => ({
      nomeExibido: nomeDe(etiqueta.title),
      original: etiqueta,
    }));
    const peloNome = picoSearch(comNome, termo, ['nomeExibido']).map(
      ({ original }) => original
    );
    return [...new Set([...peloNome, ...pelasChaves])];
  };

  // A etiqueta que o texto digitado já é: pelo título técnico (como digitado ou
  // convertido) ou pelo nome exibido. Serve ao "Criar etiqueta" do seletor.
  const etiquetaDoTexto = (lista, texto) => {
    const termo = (texto || '').trim();
    if (!termo) return null;
    const tecnico = tituloTecnicoDoNome(termo);
    return (
      lista.find(
        ({ title }) =>
          title === termo ||
          title === tecnico ||
          (ligada.value && mesmoNome(nomeDe(title), termo))
      ) || null
    );
  };

  return {
    ligada,
    celularLigado,
    vinculosDe,
    nomeDe,
    guardarNome,
    recarregar,
    buscar,
    etiquetaDoTexto,
  };
}
