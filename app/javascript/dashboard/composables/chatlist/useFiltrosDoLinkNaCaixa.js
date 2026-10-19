// Filtros pelo link na caixa de conversas (Números F2, #1883). Os botões do Números abrem a lista já filtrada:
// `?da_ia=1` = recebidas da IA; `?esperando_min=30` = esperando alguém há mais de 30 min. O servidor confere de novo
// (Crm::ConversationFinderComFiltrosDoLink); aqui, valor que a caixa não oferece é ignorado.
// Como a pasta do e-mail: o filtro vem do endereço da lista, segue ligado ao abrir uma conversa dela e desliga ao
// voltar para uma lista sem o link (pelo menu, por exemplo). Outras telas não mexem nele.
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const ESPERANDO_MIN = { MIN: 1, MAX: 1440 };
const SO_DIGITOS = valor =>
  valor !== '' && [...valor].every(c => c >= '0' && c <= '9');

// As listas comuns da caixa (as que leem GET conversations). Pastas salvas usam o filtro avançado e ficam de fora.
// Fora delas (a conversa aberta, outra tela), o filtro fica como está.
const LISTAS = [
  'home',
  'inbox_dashboard',
  'label_conversations',
  'team_conversations',
  'conversation_mentions',
  'conversation_unattended',
  'conversation_participating',
];
const PARAMETROS = ['da_ia', 'esperando_min'];

const minutosValidos = valor => {
  const texto = String(valor ?? '');
  if (!SO_DIGITOS(texto)) return null;
  const minutos = Number(texto);
  return minutos >= ESPERANDO_MIN.MIN && minutos <= ESPERANDO_MIN.MAX
    ? minutos
    : null;
};

export const filtrosDoEndereco = destino => ({
  daIa: destino?.query?.da_ia === '1',
  esperandoMin: minutosValidos(destino?.query?.esperando_min),
});

const daIa = ref(false);
const esperandoMin = ref(null);
// Um observador só, no roteador (vive o tempo todo, não depende de quem montou).
let observando = false;

const lerDoEndereco = destino => {
  if (!LISTAS.includes(destino.name)) return;
  const filtros = filtrosDoEndereco(destino);
  daIa.value = filtros.daIa;
  esperandoMin.value = filtros.esperandoMin;
};

export const useFiltrosDoLinkNaCaixa = () => {
  const route = useRoute();
  const router = useRouter();

  if (!observando) {
    observando = true;
    lerDoEndereco(route);
    router.afterEach(destino => lerDoEndereco(destino));
  }

  // Na lista, tira o link do endereço e o observador do roteador desliga o filtro (navegação cancelada não deixa a
  // lista sem filtro com o link ainda no endereço). Numa conversa aberta, o endereço não tem o link: desliga aqui.
  const limpar = async () => {
    const query = { ...(route.query || {}) };
    if (!PARAMETROS.some(chave => chave in query)) {
      daIa.value = false;
      esperandoMin.value = null;
      return;
    }
    PARAMETROS.forEach(chave => delete query[chave]);
    await router.replace({ name: route.name, params: route.params, query });
  };

  return { daIa, esperandoMin, limpar };
};
