import { watch } from 'vue';
import { lembrarDestino } from '../utils/destinoPronto';
import { marcarEnviadas } from '../utils/acharConfiraEstados';
import { erroDoDono, LIMITE_DO_PUBLICO } from './useDonoDaLista';
import { lerListasDaFolha } from '../utils/listasDaFolha';

// #2692 — as ações da folha "O que fazer com as {n} empresas?" (F1) e dos dois
// painéis que abrem de dentro dela ("Com quem ficam" e "Para onde vão"). Saiu
// de AcharConfiraPage.vue para a página caber na trava de tamanho (#677).
// Na demonstração, cada passo vira um estado ?demo= (mudarEstado); fora dela,
// o passo muda só o estado da tela.
const LUCAS = 7;
const VOLTA_DO_SUBPAINEL = {
  'folha-com-quem': 'folha-funil',
  'folha-para-onde': 'folha-sem-destino',
};

// Recusas do Público com frase própria na folha, em vez de "não deu": ninguém
// pode receber mensagem (a folha diz também quem ficou de fora e por quê),
// empresas demais de uma vez e um contato apagado enquanto a lista era
// guardada (os contatos criados até ali ficaram gravados). O código vem do
// servidor pela fonte (acharFonte.js, guardarLista).
const ERRO_DO_PUBLICO = {
  'prospecting.audience.no_rows': 'lista_ninguem',
  'prospecting.audience.too_many_leads': 'lista_demais',
  'prospecting.audience.foreign_contact': 'lista_contato_apagado',
  'prospecting.audience.audience_locked': 'lista_enviada',
  'prospecting.audience.all_already_in_list': 'lista_ja_estavam',
};

// #2775 (F6): "Para qual lista?" — a lista nova (o padrão) ou uma que já
// existe. `listas` é null até chegar do servidor; sem elas, só a nova.
export const LISTA_NOVA = 'nova';

export const folhaNova = (escolha = null, mostrarFora = false) => ({
  escolha,
  mostrarFora,
  enviando: null,
  guardando: false,
  erro: null,
  foraDoErro: [],
  listas: null,
  listaId: LISTA_NOVA,
});

export function useFolhaDaLista({
  demo,
  estado,
  fonte,
  mudarEstado,
  contaId,
  usuarioId,
  escolhidas,
  destino,
  pessoaId,
  pessoaNome,
  donoId,
  nomeLista,
  folha,
  pronto,
  subpainel,
  trocar,
}) {
  const progredir = feitas => {
    if (!folha.value?.enviando) return;
    folha.value = {
      ...folha.value,
      enviando: { ...folha.value.enviando, feitas },
    };
  };

  const enviar = async () => {
    const ids = escolhidas.value.map(empresa => empresa.id);
    folha.value = {
      ...folha.value,
      erro: null,
      foraDoErro: [],
      enviando: { feitas: 0, total: ids.length },
    };
    const resumo = await fonte.value.mandarParaFunil({
      ids,
      funilId: destino.value?.funil.id,
      etapaId: destino.value?.etapa.id,
      donoId: donoId.value,
      onProgresso: progredir,
    });
    if (!resumo.created.length && !resumo.existing.length) {
      // Dono recusado (#2694) tem frase própria; o resto é "não deu para mandar".
      const erro = erroDoDono(resumo) || 'funil';
      folha.value = { ...folha.value, enviando: null, erro };
      return;
    }
    if (!demo.value) {
      lembrarDestino(contaId.value, usuarioId.value, {
        funilId: destino.value.funil.id,
        etapaId: destino.value.etapa.id,
      });
    }
    // O nome antes de marcar: as mandadas saem das escolhidas.
    const primeiraNova = escolhidas.value.find(
      empresa => empresa.id === resumo.created[0]?.id
    );
    marcarEnviadas(trocar, resumo, {
      destino: destino.value,
      pessoa: pessoaNome.value,
    });
    pronto.value = {
      tipo: 'funil',
      n: resumo.created.length,
      jaEstavam: resumo.existing.length,
      falharam: resumo.failed.length,
      nome: primeiraNova?.nome,
    };
    folha.value = null;
    if (demo.value) {
      mudarEstado(pessoaId.value === 'voce' ? 'pronto' : 'pronto-com-lucas');
    }
  };

  const abrirFolha = () => {
    if (demo.value) mudarEstado('folha');
    else folha.value = folhaNova();
  };

  const escolherDestinoDaFolha = id => {
    if (!demo.value) {
      folha.value = { ...folha.value, escolha: id };
      return;
    }
    // O papel segue na URL; "Com quem fica · Alterar" sai das permissões dele.
    const estados = { funil: 'folha-funil', lista: 'folha-lista' };
    mudarEstado(estados[id] || 'folha');
  };

  const mandarDaFolha = () =>
    demo.value ? mudarEstado('folha-enviando') : enviar();

  // As listas que já existem, ao abrir a folha (também na demonstração): todas
  // as páginas, e quantas das escolhidas entram em cada uma. Falha ao ler não
  // trava: fica só "Lista nova".
  const carregarListas = async () => {
    let listas = [];
    try {
      listas = await lerListasDaFolha(fonte.value, escolhidas.value);
    } catch {
      listas = [];
    }
    if (folha.value) folha.value = { ...folha.value, listas };
  };
  watch(
    () => Boolean(folha.value) && folha.value.listas == null,
    precisa => {
      if (precisa) carregarListas();
    },
    { immediate: true }
  );

  // Numa lista nova, o Guardar lista de sempre; numa que já existe (#2775),
  // as empresas entram nela (quem já estava não entra de novo).
  const gravarLista = ids => {
    const listaId = folha.value.listaId ?? LISTA_NOVA;
    if (listaId === LISTA_NOVA) {
      return fonte.value.guardarLista({ nome: nomeLista.value, ids });
    }
    return fonte.value.acrescentarNaLista({ listaId, ids });
  };

  // O Público (#2695): o pronto guarda o id, para "Criar a mensagem" abrir a
  // Nova campanha com ele, e quem ficou de fora, para dizer o porquê.
  const guardarDaFolha = async () => {
    const ids = escolhidas.value
      .filter(empresa => empresa.temContato)
      .map(empresa => empresa.id);
    if (ids.length > LIMITE_DO_PUBLICO) {
      folha.value = { ...folha.value, erro: 'lista_demais', foraDoErro: [] };
      return;
    }
    folha.value = {
      ...folha.value,
      guardando: true,
      erro: null,
      foraDoErro: [],
    };
    try {
      const guardado = await gravarLista(ids);
      pronto.value = {
        tipo: 'lista',
        n: guardado.n,
        publicoId: guardado.publicoId,
        fora: guardado.fora,
        nome: guardado.lista ? guardado.nome : null,
      };
      folha.value = null;
      if (demo.value) mudarEstado('guardada');
    } catch (erro) {
      folha.value = {
        ...folha.value,
        guardando: false,
        erro: ERRO_DO_PUBLICO[erro?.codigo] || 'lista',
        foraDoErro: erro?.fora || [],
      };
    }
  };

  const abrirSubpainel = qual => {
    // Da folha, na demo, "Com quem fica" é um estado; da gaveta, abre ali mesmo.
    if (demo.value && qual === 'pessoa' && folha.value) {
      mudarEstado('folha-com-quem');
    } else subpainel.value = qual;
  };

  const fecharSubpainel = () => {
    const volta = demo.value && VOLTA_DO_SUBPAINEL[estado.value];
    if (volta) mudarEstado(volta);
    else subpainel.value = null;
  };

  const salvarPessoa = id => {
    pessoaId.value = id;
    subpainel.value = null;
    if (demo.value && folha.value) {
      mudarEstado(id === LUCAS ? 'folha-com-lucas' : 'folha-funil');
    }
  };

  const salvarDestino = novo => {
    destino.value = novo;
    subpainel.value = null;
  };

  return {
    enviar,
    abrirFolha,
    escolherDestinoDaFolha,
    mandarDaFolha,
    guardarDaFolha,
    abrirSubpainel,
    fecharSubpainel,
    salvarPessoa,
    salvarDestino,
  };
}
