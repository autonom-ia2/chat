# Os números do relatório baixado de Números › "De onde vieram os clientes" (#2001, F6 do #1871): os mesmos da tela
# (Crm::Numeros::Origens::Tela) no mesmo mês e funil, com as mesmas regras de quem vê o quê — gasto só em "Todos os
# funis" e para quem pode ver os anúncios, R$ de venda só com `sales_value_view` (#2075).
#
# A lista de clientes vai só para quem pode exportar o CRM (crm_export, dado pessoal em lote): o controller manda
# `cards_visiveis` (os cards que a pessoa vê, policy_scope) só nesse caso; sem eles, o arquivo leva só os números.
class Crm::Numeros::Origens::Relatorio::Dados
  # Linhas da lista de clientes na planilha; o resto fica de fora e a planilha diz quantas.
  LIMITE = 5_000

  attr_reader :account

  def initialize(tela, account:, cards_visiveis: nil)
    @tela = tela
    @account = account
    @cards_visiveis = cards_visiveis
  end

  def payload
    @payload ||= @tela.perform
  end

  def com_pessoas?
    !@cards_visiveis.nil?
  end

  def valores?
    !payload[:valorOculto]
  end

  def vazio?
    payload[:vazio]
  end

  def origens
    payload[:origens]
  end

  def anuncios
    payload[:anuncios]
  end

  def gasto
    payload[:gasto]
  end

  def moeda
    payload[:moeda]
  end

  def todos?
    payload.dig(:funil, :escolhido) == Crm::Numeros::Origens::Funis::TODOS
  end

  def funil_nome
    payload.dig(:funil, :nome)
  end

  # O primeiro dia do mês da tela.
  def mes
    ano, numero = payload.dig(:mes, :chave).split('-').map(&:to_i)
    Date.new(ano, numero, 1)
  end

  def zona
    @zona ||= Crm::Timezone::Resolver.new(account: @account).zone_or_default
  end

  # { total:, items: [...] }: os clientes do mês que a pessoa vê, os mais recentes primeiro; vazio sem a permissão.
  def clientes
    @clientes ||= begin
      linhas = com_pessoas? ? visiveis : []
      { total: linhas.size, items: linhas.sort_by { |linha| [-linha.created_at.to_i, -linha.id] }.first(LIMITE).map { |linha| cliente(linha) } }
    end
  end

  private

  def visiveis
    ids = @cards_visiveis.where(id: @tela.cards_do_mes.select(:id)).pluck(:id).to_set
    @tela.linhas.select { |linha| ids.include?(linha.id) }
  end

  def cliente(linha)
    {
      entrou_em: linha.created_at, card: linha.titulo, contato: contatos[linha.contact_id], funil: funis[linha.pipeline_id],
      etapa: etapas[linha.stage_id], origem: linha.tipo, anuncio: (titulos_de_anuncio[linha.ad_id] if linha.ad_id),
      situacao: situacao(linha), valor: (linha.value_cents / 100.0 if valores?)
    }
  end

  def situacao(linha)
    return :sale if linha.venda
    return :open if linha.status == 'open'

    linha.status == 'lost' ? :lost : :closed
  end

  def contatos
    @contatos ||= @account.contacts.where(id: @tela.linhas.filter_map(&:contact_id).uniq).pluck(:id, :name).to_h
  end

  def funis
    @funis ||= @account.crm_pipelines.where(id: @tela.linhas.map(&:pipeline_id).uniq).pluck(:id, :name).to_h
  end

  def etapas
    @etapas ||= Crm::PipelineStage.where(account_id: @account.id, id: @tela.linhas.filter_map(&:stage_id).uniq).pluck(:id, :name).to_h
  end

  def titulos_de_anuncio
    @titulos_de_anuncio ||= anuncios.to_h { |anuncio| [anuncio[:id], anuncio[:titulo]] }
  end
end
