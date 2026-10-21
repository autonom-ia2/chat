// Pasta aberta na caixa de e-mail (#1809, fase 1): Entrada, Spam ou Lixeira do painel.
// #1938: Enviados é uma vista (as conversas em que nós mandamos mensagem); não se move
// conversa para ela, e a conversa continua na Entrada.
// A lista guarda a pasta no endereço (`?pasta=lixeira`): voltar de uma conversa (Voltar
// do navegador ou do app) cai na mesma pasta, e recarregar também. Abrir a conversa
// mantém a pasta da lista ao lado. Vale para a caixa em que foi escolhida; em outra
// caixa, ou ao voltar para a lista pelo menu (link da caixa, sem `pasta`), é a Entrada.
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ConversaEmailPastasAPI from 'dashboard/api/pastasDoEmail';

export const PASTAS = { SPAM: 'spam', LIXEIRA: 'lixeira' };
export const ENVIADOS = 'enviados';
const VALIDAS = [...Object.values(PASTAS), ENVIADOS];
const LISTA = 'inbox_dashboard';

export const pastaDoEndereco = destino => {
  const valor = destino?.query?.pasta;
  return VALIDAS.includes(valor) ? valor : null;
};

const pasta = ref(null);
const caixaDaPasta = ref(null);
// Um observador só, no roteador (vive o tempo todo, não depende de quem montou).
let observando = false;
// Avisa a lista e o topo do e-mail que uma conversa mudou de pasta.
const versao = ref(0);

const lerDaLista = destino => {
  pasta.value = pastaDoEndereco(destino);
  caixaDaPasta.value = destino.params?.inbox_id ?? null;
};

export const usePastaDoEmail = () => {
  const route = useRoute();
  const router = useRouter();

  if (!observando) {
    observando = true;
    if (route.name === LISTA) lerDaLista(route);
    router.afterEach(destino => {
      if (destino.name === LISTA) lerDaLista(destino);
    });
  }

  const pastaAtiva = computed(() =>
    pasta.value && String(route.params.inbox_id) === String(caixaDaPasta.value)
      ? pasta.value
      : null
  );

  const abrirPasta = async (caixaId, nome = null) => {
    const destino = {
      name: LISTA,
      params: { accountId: route.params.accountId, inbox_id: caixaId },
      query: nome ? { pasta: nome } : {},
    };
    const mesmaLista =
      route.name === LISTA &&
      String(route.params.inbox_id) === String(caixaId) &&
      pastaDoEndereco(route) === nome;
    if (mesmaLista) return;
    await router.push(destino);
  };

  const moverConversa = async (conversaId, nome) => {
    const { data } = await ConversaEmailPastasAPI.mover(conversaId, nome || '');
    versao.value += 1;
    return data.pasta;
  };

  // Só para o que já está na Lixeira (o servidor confere).
  const excluirConversa = async conversaId => {
    await ConversaEmailPastasAPI.excluir(conversaId);
    versao.value += 1;
  };

  return {
    pasta: pastaAtiva,
    versao,
    abrirPasta,
    moverConversa,
    excluirConversa,
  };
};
