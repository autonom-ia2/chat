// #3057 — "Conversar" com a pessoa de um seguro: na linha da aba Seguros e na
// gaveta do seguro. É o "Conversar" da ficha (pages/FichaDaPessoaPage.vue):
// abre a conversa mais recente da pessoa, pela mesma leitura (as conversas que
// quem olha pode ler, fonte/fichaFonte.js) e pela mesma rota
// (ficha/useAcoesDaFicha.js). Se a leitura das conversas falha, conta como
// "sem conversa" (abaixo). Na demonstração as pessoas são
// inventadas: o clique só avisa, como na lista de pessoas.
//   conversar(pessoa): pessoa = { id, name }
// #3057 (2ª rodada) — quem ainda não conversou não vai mais para a ficha (lá o
// "Conversar" some sem conversa): `abrirConversaNova(pessoaId)` abre a "Nova
// conversa" já com a pessoa (components/carteira/ConversaNova.vue). Se ela não
// abre (quem olha só lê conversas, ou o contato não veio), o aviso diz que
// ainda não conversaram por aqui e que o telefone está na ficha.
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { fichaFonte } from '../fonte/fichaFonte';

export const useConversarComPessoa = ({
  demo = false,
  abrirConversaNova = async () => false,
} = {}) => {
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
    if (conversa) {
      acoes.abrirConversa(conversa.id);
      return;
    }
    if (await abrirConversaNova(pessoa.id)) return;
    useAlert(t('RELACIONAMENTOS_CARTEIRA.GAVETA.SEM_CONVERSA'));
  };
};
