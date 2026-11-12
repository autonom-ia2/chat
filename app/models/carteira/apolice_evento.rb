# Uma linha da história de uma apólice (E4, #2897): chegou pela planilha, foi corrigida, cancelada. `quando` é a hora
# do fato; `user` é quem fez (nulo: o sistema); `campaign_import` é a importação que causou. `valores` guarda o que a
# tela mostra do evento e `mudancas`, o antes e o depois de cada campo. Sem account_id: o evento é da apólice e sai com
# ela, pela chave em cascata. O banco não lista os tipos (crescem a cada etapa); a lista entra aqui com quem grava.
class Carteira::ApoliceEvento < ApplicationRecord
  self.table_name = 'carteira_apolice_eventos'

  belongs_to :apolice, class_name: 'Carteira::Apolice', inverse_of: :eventos
  belongs_to :user, optional: true
  belongs_to :campaign_import, optional: true

  validates :tipo, :quando, presence: true
end
