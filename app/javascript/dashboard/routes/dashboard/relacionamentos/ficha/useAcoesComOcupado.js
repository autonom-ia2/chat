// #3071 — como as fichas gravam (tirado de useFichaDaPessoa no #3078, para a
// ficha da empresa usar o mesmo). Cada ação devolve `true` se deu certo e
// `false` se falhou; quem chama decide o aviso. `motivo` guarda a frase que o
// servidor mandou na última falha (o DELETE do contato diz por que não apagou,
// por exemplo), ou vazio. `ocupadoEm(nome)` diz se aquela ação está gravando;
// duas ações diferentes podem estar no ar ao mesmo tempo sem uma soltar o
// "ocupado" da outra. Só a falha do servidor (a resposta, a rede, o "não
// achei") vira `false` calada: um defeito da tela vai para o Sentry, sem dado da
// pessoa, e também devolve `false`, para a tela dizer que não deu.
// `acao` recebe `aindaVale()`: se a ficha trocou de registro durante a escrita,
// o que foi gravado ficou gravado, mas a resposta velha não entra no que está
// na tela.
import { computed, ref } from 'vue';
import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';
import { NAO_ACHEI, SEM_ACESSO } from './falhas';

const FALHAS_COM_NOME = [NAO_ACHEI, SEM_ACESSO];

const veioDoServidor = falha =>
  Boolean(
    falha?.isAxiosError ||
      falha?.response ||
      falha?.cause?.response ||
      falha?.cause?.isAxiosError ||
      FALHAS_COM_NOME.includes(falha?.name)
  );

const fraseDoServidor = falha => {
  const frase =
    falha?.cause?.response?.data?.message ?? falha?.response?.data?.message;
  return typeof frase === 'string' ? frase : '';
};

export const useAcoesComOcupado = ({ geracao, tela }) => {
  const ocupados = ref(new Set());
  const motivo = ref('');

  const marcarOcupado = (nome, sim) => {
    const novos = new Set(ocupados.value);
    if (sim) novos.add(nome);
    else novos.delete(nome);
    ocupados.value = novos;
  };

  const executar = async (nome, acao) => {
    marcarOcupado(nome, true);
    motivo.value = '';
    const geracaoDoPedido = geracao();
    try {
      await acao(() => geracaoDoPedido === geracao());
      return true;
    } catch (falha) {
      if (!veioDoServidor(falha)) reportarSemDados(falha, { tela });
      motivo.value = fraseDoServidor(falha);
      return false;
    } finally {
      marcarOcupado(nome, false);
    }
  };

  return {
    executar,
    motivo,
    ocupadoEm: nome => ocupados.value.has(nome),
    algumOcupado: computed(() => ocupados.value.size > 0),
  };
};
