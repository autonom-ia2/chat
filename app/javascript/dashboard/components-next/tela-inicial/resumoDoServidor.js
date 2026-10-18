import TelaInicialAPI from 'dashboard/api/telaInicial';

// #1801 — os números da tela inicial, contados no servidor (GET tela_inicial/resumo).
// `foraDoPrazo` null = a conta não usa prazos; `equipe` null = a pessoa não vê os totais da conta.
const numero = valor => Number(valor) || 0;
const numeroOuNulo = valor =>
  valor === null || valor === undefined ? null : numero(valor);

const daEquipe = equipe =>
  equipe
    ? {
        esperam: numero(equipe.esperam),
        semResponsavel: numero(equipe.sem_responsavel),
        foraDoPrazo: numeroOuNulo(equipe.fora_do_prazo),
      }
    : null;

const daProxima = proxima =>
  proxima
    ? {
        displayId: proxima.display_id,
        nome: proxima.nome_do_contato || '',
        desde: numero(proxima.waiting_since),
      }
    : null;

export const lerResumo = dados => ({
  comVoce: numero(dados?.com_voce),
  esperamVoce: numero(dados?.esperam),
  semResponsavel: numero(dados?.sem_responsavel),
  foraDoPrazo: numeroOuNulo(dados?.fora_do_prazo),
  proxima: daProxima(dados?.proxima),
  equipe: daEquipe(dados?.equipe),
});

export const buscarResumo = async () => {
  const { data } = await TelaInicialAPI.resumo();
  return lerResumo(data);
};
