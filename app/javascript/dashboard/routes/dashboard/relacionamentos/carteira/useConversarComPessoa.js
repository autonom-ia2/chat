// #3057 — "Conversar" com a pessoa de um seguro: na linha da aba Seguros e na
// gaveta do seguro. É o "Conversar" da ficha (pages/FichaDaPessoaPage.vue):
// abre a conversa mais recente da pessoa, pela mesma leitura (as conversas que
// quem olha pode ler, fonte/fichaFonte.js) e pela mesma rota
// (ficha/useAcoesDaFicha.js). Quem ainda não conversou vai para a ficha da
// pessoa: começar conversa nova não é só uma rota (#2970), e a ficha mostra o
// telefone e as conversas. Se a leitura das conversas falha, também: a ficha
// diz o que houve e deixa tentar de novo. Na demonstração as pessoas são
// inventadas: o clique só avisa, como na lista de pessoas.
//   conversar(pessoa): pessoa = { id, name }
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { fichaFonte } from '../fonte/fichaFonte';

export const useConversarComPessoa = ({ demo = false } = {}) => {
  const { t } = useI18n();
  const acoes = useAcoesDaFicha();
  const fonte = fichaFonte();

  const conversaMaisRecente = async pessoaId => {
    try {
      const [maisRecente] = await fonte.conversas(pessoaId);
      return maisRecente ?? null;
    } catch {
      return null;
    }
  };

  return async pessoa => {
    if (demo) {
      useAlert(
        t('RELACIONAMENTOS.LISTA.LINHA.ABRINDO_CONVERSA', { nome: pessoa.name })
      );
      return;
    }
    const conversa = await conversaMaisRecente(pessoa.id);
    if (conversa) acoes.abrirConversa(conversa.id);
    else acoes.abrirPessoa(pessoa.id);
  };
};
