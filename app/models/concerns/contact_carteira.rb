# Carteira de seguros (E4, #2897): os seguros da pessoa. Apagar o contato apaga as apólices dele pelo app, uma a uma:
# a chave `carteira_apolices.contact_id` não tem cascata de propósito, porque a apólice guarda um PDF e a cascata do
# banco apagaria a linha e deixaria o arquivo no armazenamento. Vale para todo caminho que destrói o contato com
# callbacks (DELETE contacts/:id, exclusão em lote, mescla). Na mescla as apólices passam antes para o contato que fica
# (ContactMergeAction), e na exclusão da conta elas saem antes dos contatos (Autonomia::ExclusaoDaConta).
module ContactCarteira
  extend ActiveSupport::Concern

  included do
    has_many :apolices, class_name: 'Carteira::Apolice', dependent: :destroy
  end
end
