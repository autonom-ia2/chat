# Uma linha da história de uma apólice (E4, #2897): chegou pela planilha, foi corrigida, cancelada. `quando` é a hora
# do fato; `user` é quem fez (nulo: o sistema); `campaign_import` é a importação que causou. `valores` guarda o que a
# tela mostra do evento e `mudancas`, o antes e o depois de cada campo. Sem account_id: o evento é da apólice e sai com
# ela, pela chave em cascata. O banco não lista os tipos (crescem a cada etapa); a lista entra aqui com quem grava.
class Carteira::ApoliceEvento < ApplicationRecord
  self.table_name = 'carteira_apolice_eventos'

  # E4: chegou pela planilha (a primeira vez e de novo, com o que mudou), foi corrigido na tela, cancelado, voltou a
  # ativo, ganhou o PDF e ficou sem ele.
  TIPOS = %w[chegou_planilha chegou_de_novo corrigido cancelado voltou_a_ativo pdf_anexado pdf_tirado].freeze

  belongs_to :apolice, class_name: 'Carteira::Apolice', inverse_of: :eventos
  belongs_to :user, optional: true
  belongs_to :campaign_import, optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validates :quando, presence: true
end
