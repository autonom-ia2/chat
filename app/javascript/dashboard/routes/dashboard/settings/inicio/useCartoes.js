import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import { useOnboardingTrail } from 'dashboard/composables/useOnboardingTrail';
import { useMenuPublicado } from 'dashboard/components-next/sidebar/fork/menuPublicado';
import { FILHOS_CONHECIDOS } from 'dashboard/components-next/sidebar/forkSidebarMenu';
import { GRUPOS_DE_CARTOES } from './cartoes';
import { agenteIaPorCaixaLigado } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useAgenteIaPorCaixa';

// Os cartões da página inicial de Configurações (#1617): quais a pessoa vê, para onde levam, e o estado de
// cada um com o dado que já está à mão (a trilha de Primeiros passos e as listas que o menu já carrega).

const CONTAGENS = {
  caixas: 'inboxes/getInboxes',
  usuarios: 'agents/getAgents',
  times: 'teams/getTeams',
  etiquetas: 'labels/getLabels',
};

// Sem acento e sem maiúscula, para "horario" achar "Horários". Comparação por `includes`, sem regex.
const LETRA_COM_ACENTO_DE = 0x300;
const LETRA_COM_ACENTO_ATE = 0x36f;
export const normalizar = texto =>
  [...(texto || '').normalize('NFD').toLocaleLowerCase('pt-BR')]
    .filter(letra => {
      const codigo = letra.charCodeAt(0);
      return codigo < LETRA_COM_ACENTO_DE || codigo > LETRA_COM_ACENTO_ATE;
    })
    .join('')
    .trim();

// O que a instalação precisa ter ligado para a tela do cartão abrir (o beforeEnter da rota confere o mesmo).
const EXIGENCIAS = {
  crm: () => window.globalConfig?.CRM_KANBAN_ENABLED === 'true',
  campanhasPorEmail: () =>
    window.globalConfig?.EMAIL_CAMPAIGN_ENABLED === 'true' &&
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true',
  semAgenteIaPorCaixa: store =>
    !agenteIaPorCaixaLigado(
      store.getters['accounts/getAccount']?.(store.getters.getCurrentAccountId)
    ),
};

const minuscula = texto =>
  texto ? texto.charAt(0).toLocaleLowerCase('pt-BR') + texto.slice(1) : '';

export function useCartoes() {
  const { t } = useI18n();
  const store = useStore();
  const { podeAbrir } = usePodeAbrir();
  const menu = useMenuPublicado();
  const trilha = useOnboardingTrail();
  const termo = ref('');

  onMounted(() => {
    trilha.carregar();
    store.dispatch('agents/get');
  });

  // Itens do menu de sempre por `name`: os do topo e os filhos de Configurações.
  const indice = computed(() => {
    const mapa = new Map();
    (menu.value || []).forEach(item => {
      mapa.set(item.name, item);
      if (item.name === 'Settings') {
        (item.children || []).forEach(filho => mapa.set(filho.name, filho));
      }
    });
    return mapa;
  });

  const destinoDe = item =>
    item.to || (item.children || []).find(filho => podeAbrir(filho.to))?.to;

  const passoDe = id => trilha.passos.value.find(passo => passo.id === id);

  const contar = chave => {
    const lista = store.getters[CONTAGENS[chave]];
    return Array.isArray(lista) ? lista.length : 0;
  };

  // Caixas que pedem reconexão: já vêm na lista de caixas do menu (`reauthorization_required`), sem chamada nova.
  const paraReconectar = () =>
    (store.getters['inboxes/getInboxes'] || []).filter(
      caixa => caixa.reauthorization_required
    ).length;

  // Estado do cartão: o que falta (âmbar), erro (vermelho), pronto (verde) ou só um dado (neutro).
  const estadoDe = cartao => {
    const passo = cartao.passo ? passoDe(cartao.passo) : null;
    const quebradas = cartao.saude ? paraReconectar() : 0;
    if (quebradas > 0) {
      return {
        tipo: 'erro',
        texto: t('SETTINGS_INICIO.RECONECTAR', { count: quebradas }, quebradas),
      };
    }
    if (passo?.status === 'pendente') {
      return {
        tipo: 'falta',
        texto: t('SETTINGS_INICIO.FALTA', { item: minuscula(passo.titulo) }),
      };
    }
    if (cartao.contagem) {
      const numero = contar(cartao.contagem);
      return {
        tipo: numero > 0 || passo ? 'pronto' : 'neutro',
        texto: t(
          `SETTINGS_INICIO.CONTAGEM.${cartao.contagem}`,
          { count: numero },
          numero
        ),
      };
    }
    if (passo) return { tipo: 'pronto', texto: t('SETTINGS_INICIO.PRONTO') };
    if (cartao.nota) {
      return {
        tipo: 'neutro',
        texto: t(`SETTINGS_INICIO.NOTAS.${cartao.nota}`),
      };
    }
    return null;
  };

  const destinoDoCartao = cartao => {
    if (cartao.rota) return { name: cartao.rota };
    const item = indice.value.get(cartao.origem);
    return item && destinoDe(item);
  };

  const montarCartao = (cartao, grupo) => {
    if (cartao.exige && !EXIGENCIAS[cartao.exige](store)) return null;
    const to = destinoDoCartao(cartao);
    if (!to || !podeAbrir(to)) return null;
    return {
      id: cartao.id,
      grupo,
      to,
      icone: cartao.icone,
      titulo: t(`SETTINGS_INICIO.CARTOES.${cartao.id}.TITULO`),
      texto: t(`SETTINGS_INICIO.CARTOES.${cartao.id}.TEXTO`),
      estado: estadoDe(cartao),
    };
  };

  // Configuração nova do Chatwoot que ainda não tem cartão: aparece em "Outros", nunca some.
  const outros = computed(() =>
    (indice.value.get('Settings')?.children || [])
      .filter(filho => !FILHOS_CONHECIDOS.Settings.includes(filho.name))
      .filter(filho => podeAbrir(filho.to))
      .map(filho => ({
        id: filho.name,
        grupo: 'OUTROS',
        to: filho.to,
        icone:
          typeof filho.icon === 'string' ? filho.icon : 'i-lucide-settings',
        titulo: filho.label,
        texto: t('SETTINGS_INICIO.OUTRO_ITEM'),
        estado: null,
      }))
  );

  const grupos = computed(() => {
    const montados = GRUPOS_DE_CARTOES.map(grupo => ({
      id: grupo.id,
      titulo: t(`SETTINGS_INICIO.GRUPOS.${grupo.id}`),
      cartoes: grupo.cartoes
        .map(cartao => montarCartao(cartao, grupo.id))
        .filter(Boolean),
    }));
    if (outros.value.length) {
      montados.push({
        id: 'OUTROS',
        titulo: t('SETTINGS_INICIO.GRUPOS.OUTROS'),
        cartoes: outros.value,
      });
    }
    return montados.filter(grupo => grupo.cartoes.length);
  });

  const termoNormalizado = computed(() => normalizar(termo.value));
  const buscando = computed(() => termoNormalizado.value.length > 0);

  const gruposFiltrados = computed(() => {
    if (!buscando.value) return grupos.value;
    return grupos.value
      .map(grupo => ({
        ...grupo,
        cartoes: grupo.cartoes.filter(cartao =>
          normalizar(
            `${cartao.titulo} ${cartao.texto} ${grupo.titulo}`
          ).includes(termoNormalizado.value)
        ),
      }))
      .filter(grupo => grupo.cartoes.length);
  });

  const encontrados = computed(() =>
    gruposFiltrados.value.reduce(
      (soma, grupo) => soma + grupo.cartoes.length,
      0
    )
  );

  // "Comece por aqui": só a primeira pendência, na ordem dos cartões.
  const primeiraPendencia = computed(
    () =>
      grupos.value
        .flatMap(grupo => grupo.cartoes)
        .find(cartao => ['erro', 'falta'].includes(cartao.estado?.tipo)) || null
  );

  const carregado = computed(() => Boolean(menu.value));

  return {
    termo,
    buscando,
    grupos: gruposFiltrados,
    encontrados,
    primeiraPendencia,
    trilhaCarregada: computed(() => trilha.total.value > 0),
    carregado,
  };
}
