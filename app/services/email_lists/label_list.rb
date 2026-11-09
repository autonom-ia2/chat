# A etiqueta da lista de e-mail (G52, #2760). Incluído no Label por config/initializers/email_lists.rb, sem mexer no
# modelo do upstream.
#
# Apagar a etiqueta (Api::V1::Accounts::LabelsController#destroy usa `destroy!`) apaga a lista pelo Rails, para o
# before_destroy da lista tirar dela as campanhas que ainda não mandaram nada. A tela de etiquetas recusa apagar a
# etiqueta de uma lista em uso (EmailLists::LabelDestroyGuard). A cascata da chave do banco continua como rede de
# segurança para quem apaga sem callbacks.
#
# O título é o público da campanha (EmailList#contatos lê a etiqueta pelo título). Por isso:
# - a etiqueta de uma lista não troca de título: renomear pela tela de etiquetas mudaria quem recebe a campanha sem a
#   lista mudar de nome;
# - o prefixo "lista-email-" é só das listas na tela de etiquetas: lá não se cria nem se renomeia etiqueta com ele.
#   Isso não fecha o nome: a etiqueta do contato aceita qualquer nome, sem passar por aqui. Quem protege a lista nova é
#   EmailList.criar, que nunca reaproveita etiqueta existente nem nome que já está em contato.
module EmailLists::LabelList
  extend ActiveSupport::Concern

  included do
    has_one :email_list, dependent: :destroy, inverse_of: :label

    # Marcado só por EmailList.criar, ao criar a etiqueta da lista.
    attribute :da_lista_de_email, :boolean, default: false

    validate :titulo_da_lista_de_email, if: :will_save_change_to_title?
  end

  private

  def titulo_da_lista_de_email
    if persisted? && email_list.present?
      errors.add(:title, :email_list_locked)
    elsif !da_lista_de_email && title.to_s.start_with?("#{EmailList::PREFIXO_DA_ETIQUETA}-")
      errors.add(:title, :email_list_reserved)
    end
  end
end
