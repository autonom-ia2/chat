import { ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useTextos } from '../guiada/useTextos';
import { explicar401 } from '../salvarFuncao';

// O "Salvar" da gaveta de pessoas (#2308, especificação 5.D). Manda só custom_role_id (null para sem função): reenviar
// o nome lido da lista desfaria uma troca de nome feita em paralelo. Depois, recarrega as pessoas e confere nelas que
// cada uma ficou na função pedida; o 200 sozinho não prova (sem custom_roles na conta, o servidor ignora a função).
// O que não gravou volta para `mudancas`, com o motivo e o nome de cada um:
// - 401 com a sessão boa: o agents/update nunca manda código, e a única recusa possível ali é o alcance de quem dá
//   (GrantGuard); a tela recarrega também as funções, para a que saiu do alcance sumir da escolha;
// - 401 com a sessão vencida: o app vai para o login, sem mensagem;
// - o resto (rede): tente de novo.
const NAO_AUTORIZADO = 401;

export function useSalvarGaveta(mudancas) {
  const store = useStore();
  const { t, lista } = useTextos();
  const agentes = useMapGetter('agents/getAgents');
  const salvando = ref(false);
  const erro = ref('');

  const nomeDe = id => agentes.value.find(item => item.id === id)?.name;
  const nomesDe = pedidos => lista(pedidos.map(([id]) => nomeDe(id)));
  const funcaoDe = id =>
    agentes.value.find(item => item.id === id)?.custom_role_id ?? null;

  const enviar = pedidos =>
    Promise.allSettled(
      pedidos.map(([id, destino]) =>
        store.dispatch('agents/update', { id, custom_role_id: destino })
      )
    );

  // Separa os pedidos pelo que aconteceu: gravados, recusados (401) e caídos (o resto).
  const separar = (pedidos, resultados) => {
    const com = condicao => pedidos.filter((_, i) => condicao(resultados[i]));
    const recusa = resultado =>
      resultado.status === 'rejected' &&
      resultado.reason?.status === NAO_AUTORIZADO;
    return {
      gravados: com(resultado => resultado.status === 'fulfilled'),
      recusados: com(recusa),
      caidos: com(r => r.status === 'rejected' && !recusa(r)),
      codigo: resultados.find(recusa)?.reason?.code,
    };
  };

  const frases = ({ foraDoAlcance, caidos, semEfeito }) =>
    [
      foraDoAlcance.length &&
        t('FUNCOES_EQUIPE.GAVETA.FORA_DO_ALCANCE', {
          nomes: nomesDe(foraDoAlcance),
        }),
      caidos.length &&
        t(
          'FUNCOES_EQUIPE.GAVETA.ERRO_PARCIAL',
          { nomes: nomesDe(caidos), motivo: t('FUNCOES_EQUIPE.GAVETA.TENTE') },
          caidos.length
        ),
      semEfeito.length &&
        t(
          'FUNCOES_EQUIPE.GAVETA.NAO_MUDOU',
          { nomes: nomesDe(semEfeito) },
          semEfeito.length
        ),
    ]
      .filter(Boolean)
      .join(' ');

  // Devolve true quando tudo gravou; false deixa a gaveta aberta (com o erro, ou indo para o login).
  const salvar = async () => {
    salvando.value = true;
    erro.value = '';
    const pedidos = [...mudancas.value];
    const { gravados, recusados, caidos, codigo } = separar(
      pedidos,
      await enviar(pedidos)
    );
    const motivo = recusados.length ? (await explicar401(codigo)).erro : '';
    if (motivo === null) {
      salvando.value = false;
      return false;
    }
    const rede = motivo === 'REDE';
    await Promise.all([
      store.dispatch('agents/get'),
      ...(recusados.length ? [store.dispatch('customRole/getCustomRole')] : []),
    ]);
    const falhas = {
      foraDoAlcance: rede ? [] : recusados,
      caidos: rede ? [...caidos, ...recusados] : caidos,
      semEfeito: gravados.filter(([id, destino]) => funcaoDe(id) !== destino),
    };
    const pendentes = Object.values(falhas).flat();
    mudancas.value = new Map(pendentes);
    erro.value = frases(falhas);
    salvando.value = false;
    return !pendentes.length;
  };

  return { salvando, erro, salvar };
}
