import { lembrarDestino } from '../utils/destinoPronto';

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

export const folhaNova = (escolha = null, mostrarFora = false) => ({
  escolha,
  mostrarFora,
  enviando: null,
  guardando: false,
  erro: null,
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
  nomeLista,
  folha,
  pronto,
  subpainel,
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
      enviando: { feitas: 0, total: ids.length },
    };
    const resumo = await fonte.value.mandarParaFunil({
      ids,
      funilId: destino.value?.funil.id,
      etapaId: destino.value?.etapa.id,
      onProgresso: progredir,
    });
    if (!resumo.created.length && !resumo.existing.length) {
      folha.value = { ...folha.value, enviando: null, erro: 'funil' };
      return;
    }
    if (!demo.value) {
      lembrarDestino(contaId.value, usuarioId.value, {
        funilId: destino.value.funil.id,
        etapaId: destino.value.etapa.id,
      });
    }
    pronto.value = {
      tipo: 'funil',
      n: resumo.created.length,
      jaEstavam: resumo.existing.length,
      nome: escolhidas.value[0]?.nome,
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

  const guardarDaFolha = async () => {
    folha.value = { ...folha.value, guardando: true, erro: null };
    try {
      const ids = escolhidas.value
        .filter(empresa => empresa.temContato)
        .map(empresa => empresa.id);
      await fonte.value.guardarLista({ nome: nomeLista.value, ids });
      pronto.value = { tipo: 'lista', n: ids.length };
      folha.value = null;
      if (demo.value) mudarEstado('guardada');
    } catch {
      folha.value = { ...folha.value, guardando: false, erro: 'lista' };
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
