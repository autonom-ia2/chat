# Uma linha da história de uma apólice (E4, #2897): chegou pela planilha, foi corrigida, cancelada. `quando` é a hora
# do fato; `user` é quem fez (nulo: o sistema); `campaign_import` é a importação que causou. `valores` guarda o que a
# tela mostra do evento e `mudancas`, o antes e o depois de cada campo. Sem account_id: o evento é da apólice e sai com
# ela, pela chave em cascata. O banco não lista os tipos (crescem a cada etapa); a lista fica aqui, inteira.
class Carteira::ApoliceEvento < ApplicationRecord
  self.table_name = 'carteira_apolice_eventos'

  # Todos os passos que o catálogo da tela nomeia (`HISTORIA.TIPOS` de relacionamentosCarteira.json, já com os do
  # protótipo da carteira, #2937), de uma vez: cada etapa passa a gravar os dela sem mexer nesta lista.
  # E4: chegou pela planilha (a primeira vez e de novo, com o que mudou), foi corrigido na tela, cancelado, voltou a
  # ativo, ganhou o PDF e ficou sem ele.
  DA_E4 = %w[chegou_planilha chegou_de_novo corrigido cancelado voltou_a_ativo pdf_anexado pdf_tirado].freeze
  # E5 a E9: a renovação no funil, a proposta, os avisos ao cliente, a apólice nova e a chegada pelo conector.
  # `desfez_desfecho` (E5, #2898): alguém desfez o "renovou" ou o "não renovou"; `valores.anterior` diz qual era.
  DAS_PROXIMAS = %w[
    chegou_agger card_nasceu respondeu_algo_mudou proposta_pronta proposta_enviada cliente_respondeu endosso renovou
    nao_renovou nao_renovou_outro apolice_nova cotacao_pedida proposta_enviada_sozinha proposta_nao_saiu aviso_nao_saiu
    algo_mudou_nao_saiu palavras_nao_saiu proposta_pedida proposta_anexada palavras_enviadas parcela_avisada
    desfez_desfecho
  ].freeze
  TIPOS = (DA_E4 + DAS_PROXIMAS).freeze

  belongs_to :apolice, class_name: 'Carteira::Apolice', inverse_of: :eventos
  belongs_to :user, optional: true
  belongs_to :campaign_import, optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validates :quando, presence: true
end
