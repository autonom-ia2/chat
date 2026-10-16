# Canais de cada funil (#1140, correção 1): quem receberia as conversas de cada assunto da caixa se a tela salvasse agora.
# A regra é a do motor de entrega (Crm::Entrega::QuemCuida.na_caixa), com as linhas de acesso que o Gravador gravaria
# (Crm::Caixas::Gravador#acessos_previstos). Nada é gravado.
#
#   { triagem: [user_id, ...], funis: { pipeline_id => [user_id, ...] } }
#
# `triagem`: conversa ainda sem card. `funis`: um por funil que a tela marcou, na ordem dela.
class Crm::Caixas::QuemRecebe
  def initialize(account:, inbox:, dados:)
    @account = account
    @inbox = inbox
    @dados = dados
  end

  def perform
    acessos = acessos_depois_de_salvar
    {
      triagem: ids(nil, acessos),
      funis: pipeline_ids.index_with { |pipeline_id| ids(pipeline_id, acessos) }
    }
  end

  private

  # As linhas que restringem, como o motor lê (Crm::Entrega::QuemCuida#acessos_por_pessoa), com as da tela por cima.
  # Quem a tela não mandou fica como está no banco; quem vai cuidar de tudo (nil) sai.
  def acessos_depois_de_salvar
    gravadas = Crm::InboxAgentAccess.where(account_id: @account.id, inbox_id: @inbox.id).includes(:agent_pipelines).select(&:restricts?)
    previstas = Crm::Caixas::Gravador.new(account: @account, inbox: @inbox, user: nil, dados: @dados).acessos_previstos
    gravadas.index_by(&:user_id).merge(previstas).compact
  end

  def ids(pipeline_id, acessos)
    Crm::Entrega::QuemCuida.na_caixa(inbox: @inbox, pipeline_id: pipeline_id, acessos: acessos).map(&:id)
  end

  # Só funis ativos da conta: os outros o Gravador recusaria.
  def pipeline_ids
    marcados = Array(@dados[:pipeline_ids]).map(&:to_i).uniq
    ativos = @account.crm_pipelines.active.where(id: marcados).pluck(:id)
    marcados & ativos
  end
end
