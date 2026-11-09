# A etiqueta da lista de e-mail (G52, #2760). Incluído no Label por config/initializers/email_lists.rb, sem mexer no
# modelo do upstream.
#
# Apagar a etiqueta (Api::V1::Accounts::LabelsController#destroy usa `destroy!`) apaga a lista pelo Rails, para o
# before_destroy da lista tirar dela as campanhas que ainda não mandaram nada. A cascata da chave do banco continua
# como rede de segurança para quem apaga sem callbacks.
module EmailLists::LabelList
  extend ActiveSupport::Concern

  included do
    has_one :email_list, dependent: :destroy, inverse_of: :label
  end
end
