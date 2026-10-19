// Ações do cartão de contato da pele (#1702): "Salvar contato" e "Conversar". Saíram do
// bubbles/Contact.vue para servirem também a cada contato da janela "Ver todos" de
// vários contatos (ContatosDoWhatsapp), com o mesmo comportamento.
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import { useI18n } from 'vue-i18n';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

export const soDigitos = texto =>
  Array.from(String(texto ?? ''))
    .filter(caractere => caractere >= '0' && caractere <= '9')
    .join('');

// Cadastro sem nome de verdade: vazio ou o próprio telefone no lugar do nome.
const semNome = (contato, digitos) =>
  !contato.name?.trim() || soDigitos(contato.name) === digitos;

export const useAcoesDoContato = () => {
  const store = useStore();
  const { t } = useI18n();
  const { canManageRelationshipRecords } = useRelationshipPermissions();

  const buscarPorTelefone = async telefone => {
    const query = {
      attribute_key: 'phone_number',
      filter_operator: 'equal_to',
      values: [telefone],
      attribute_model: 'standard',
      custom_attribute_type: '',
    };
    const contatos = await store.dispatch('contacts/filter', {
      queryPayload: { payload: [query] },
      resetState: false,
    });
    return contatos.shift();
  };

  // Procura o contato pelo telefone com "+" (como ele é gravado) e cria se não existir.
  // Achou sem nome de verdade e o cartão traz o nome? Completa o cadastro; nome que
  // alguém já deu ao contato não é trocado.
  const acharOuCriar = async (digitos, nome) => {
    const contato = await buscarPorTelefone(`+${digitos}`);
    // Quem só vê contatos não cadastra (#1849): diz o caminho em vez do erro cru.
    if (!contato && !canManageRelationshipRecords.value)
      throw new ExceptionWithMessage(t('CONVERSA_CANAL.CONTATO.SEM_CADASTRO'));
    if (!contato) {
      const criado = await store.dispatch('contacts/create', {
        name: nome,
        phone_number: `+${digitos}`,
      });
      useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
      return criado;
    }
    if (nome && semNome(contato, digitos)) {
      await store.dispatch('contacts/update', { id: contato.id, name: nome });
      useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
    }
    return contato;
  };

  const abrirContato = id => {
    const conta = window.location.pathname.split('/')[3];
    window.open(`/app/accounts/${conta}/contacts/${id}`, '_blank');
  };

  const avisarErro = erro => {
    if (erro instanceof DuplicateContactException) {
      if (erro.data.includes('phone_number')) {
        useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
      }
    } else if (erro instanceof ExceptionWithMessage) {
      useAlert(erro.data);
    } else {
      useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
    }
  };

  // "Salvar contato": acha ou cria e abre a ficha numa aba nova.
  const salvar = async (digitos, nome) => {
    try {
      const contato = await acharOuCriar(digitos, nome);
      abrirContato(contato.id);
    } catch (erro) {
      avisarErro(erro);
    }
  };

  // "Conversar": acha ou cria e devolve o id para a Nova conversa (null se falhou).
  const paraConversar = async (digitos, nome) => {
    try {
      const contato = await acharOuCriar(digitos, nome);
      return String(contato.id);
    } catch (erro) {
      avisarErro(erro);
      return null;
    }
  };

  return { buscarPorTelefone, abrirContato, avisarErro, salvar, paraConversar };
};
