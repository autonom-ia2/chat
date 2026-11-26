# == Schema Information
#
# Table name: autonomia_cotacoes_de_viagem
#
#  id                 :bigint           not null, primary key
#  pedido             :jsonb            not null
#  planos             :jsonb            not null
#  proposta           :jsonb
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#  conversation_id    :bigint           not null
#  id_cotacao         :string           not null
#
# Indexes
#
#  index_autonomia_cotacoes_de_viagem_on_account_id             (account_id)
#  index_autonomia_cotacoes_de_viagem_on_autonomia_agent_id     (autonomia_agent_id)
#  index_autonomia_cotacoes_de_viagem_on_conversation_id_and_id (conversation_id,id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
# A cotação de viagem de uma conversa (#3211). `pedido` guarda os nossos parâmetros já conferidos (destinos, datas,
# idades, motivo) e, em 'universal', o pedido enviado à seguradora; `planos` é a lista devolvida; `proposta` fica nula
# até a proposta sair. Sem callbacks: quem grava é o serviço da cotação.
class Autonomia::Agents::CotacaoDeViagem < ApplicationRecord
  self.table_name = 'autonomia_cotacoes_de_viagem'

  belongs_to :account
  belongs_to :conversation
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id, inverse_of: false

  # A última cotação DESTE agente na conversa: a de outro agente (que cotou com outro login, de outra corretora) não
  # vira proposta nem detalhe com o login deste.
  def self.ultima_da_conversa(conversation_id, agent_id)
    where(conversation_id: conversation_id, autonomia_agent_id: agent_id).order(:id).last
  end

  # A ÚLTIMA cotação deste agente na conversa, quando é de HOJE (no fuso da conta) e da mesma viagem de `pedido`; senão
  # nil (#3223): a mesma viagem pedida de novo no dia não chama a seguradora nem manda outro PDF. Só a última, porque a
  # proposta e os detalhes leem a última (`ultima_da_conversa`): numa sequência A, B, A, devolver a 1ª A deixaria a
  # proposta sair da B.
  def self.da_mesma_viagem(conversation_id, agent_id, pedido, fuso:)
    ultima = ultima_da_conversa(conversation_id, agent_id)
    return nil if ultima.nil? || !ultima.do_dia?(fuso) || viagem(ultima.pedido) != viagem(pedido)

    ultima
  end

  # O que identifica a viagem: os destinos em ordem alfabética, a ida, a volta, as idades na ordem e o motivo.
  def self.viagem(pedido)
    dados = pedido.to_h
    [dados['destinos'].to_a.sort, dados['data_saida'], dados['data_retorno'], dados['idades'].to_a, dados['motivo'].presence]
  end

  def plano(codigo)
    planos.to_a.find { |plano| plano['codigo'] == codigo }
  end

  def do_dia?(fuso)
    created_at.in_time_zone(fuso).to_date == fuso.today
  end

  def idades
    pedido.to_h['idades'].to_a
  end
end
