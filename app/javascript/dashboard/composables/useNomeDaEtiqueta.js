import { computed, getCurrentInstance, ref, watch } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import {
  mesmoNome,
  nomeDaEtiqueta,
  tituloTecnicoDoNome,
} from 'dashboard/helper/nomeDaEtiqueta';

// Nome livre das etiquetas (#1823, F1a), atrás da flag `etiquetas_do_whatsapp`.
// Uma carga por conta para todos os chips da tela; quem cria ou edita atualiza o
// cache na hora. Os outros atendentes veem o nome novo ao recarregar o painel ou
// ao reabrir Configurações › Etiquetas (`recarregar`). Sem websocket.
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
      // Falhou: a tela segue com o que já tinha (ou o nome derivado do título),
      // sem nova tentativa a cada chip; Configurações › Etiquetas tenta de novo.
      if (!nomesPorConta.value[accountId]) comNomes(accountId, {});
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

// A store vem da instância, lida com cuidado (como no useHorarioUnicoCaixa):
// montado sem a store do painel, a flag conta como desligada e nada muda.
export function useNomeDaEtiqueta() {
  const instancia = getCurrentInstance();
  const getter = nome => instancia?.proxy?.$store?.getters?.[nome];

  const accountId = computed(() => getter('getCurrentAccountId'));
  const ligada = computed(() =>
    Boolean(
      accountId.value &&
        getter('accounts/isFeatureEnabledonAccount')?.(
          accountId.value,
          FEATURE_FLAGS.ETIQUETAS_DO_WHATSAPP
        )
    )
  );

  if (instancia) {
    watch(
      [ligada, accountId],
      ([estaLigada, conta]) => {
        if (estaLigada) carregar(conta);
      },
      { immediate: true }
    );
  }

  const etiquetas = computed(() => getter('labels/getLabels') || []);
  // Só o que é etiqueta da conta ganha nome: `Label.vue` e o chip antigo também
  // mostram texto que não é etiqueta (SLA, Linear) e esse fica como está.
  const idPorTitulo = computed(
    () => new Map(etiquetas.value.map(({ id, title }) => [title, id]))
  );
  const nomesDaConta = computed(
    () => nomesPorConta.value[accountId.value] || {}
  );

  const nomeDe = titulo => {
    if (!ligada.value || !idPorTitulo.value.has(titulo)) return titulo;
    const nomeGuardado = nomesDaConta.value[idPorTitulo.value.get(titulo)];
    return nomeDaEtiqueta(titulo, { nomeGuardado });
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
    ligada.value ? carregar(accountId.value, { forcar: true }) : null;

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
    nomeDe,
    guardarNome,
    recarregar,
    buscar,
    etiquetaDoTexto,
  };
}
