// Pasta aberta na caixa de e-mail (#1809, fase 1): Entrada, Spam ou Lixeira do painel.
// Fica num estado da tela, não no endereço: abrir uma conversa a partir do Spam não
// pode jogar a lista de volta para a Entrada. Vale para a caixa em que foi escolhida;
// em outra caixa, ou ao voltar para a lista pelo menu (link da caixa), é a Entrada.
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ConversaEmailPastasAPI from 'dashboard/api/pastasDoEmail';

export const PASTAS = { SPAM: 'spam', LIXEIRA: 'lixeira' };

const pasta = ref(null);
const caixaDaPasta = ref(null);
// Navegação feita por nós (escolher pasta): o observador da rota não zera a pasta.
let navegandoParaPasta = false;
// Um observador só, no roteador (vive o tempo todo, não depende de quem montou).
let observando = false;
// Avisa a lista e o topo do e-mail que uma conversa mudou de pasta.
const versao = ref(0);

export const usePastaDoEmail = () => {
  const route = useRoute();
  const router = useRouter();

  const pastaAtiva = computed(() =>
    pasta.value && String(route.params.inbox_id) === String(caixaDaPasta.value)
      ? pasta.value
      : null
  );

  // Voltou para a lista da caixa por outro caminho (o link da caixa): Entrada.
  if (!observando) {
    observando = true;
    router.afterEach(destino => {
      if (navegandoParaPasta) {
        navegandoParaPasta = false;
        return;
      }
      if (destino.name === 'inbox_dashboard') pasta.value = null;
    });
  }

  const abrirPasta = async (caixaId, nome = null) => {
    pasta.value = nome;
    caixaDaPasta.value = caixaId;
    const naLista =
      route.name === 'inbox_dashboard' &&
      String(route.params.inbox_id) === String(caixaId);
    if (naLista) return;
    navegandoParaPasta = true;
    await router.push({
      name: 'inbox_dashboard',
      params: { accountId: route.params.accountId, inbox_id: caixaId },
    });
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
