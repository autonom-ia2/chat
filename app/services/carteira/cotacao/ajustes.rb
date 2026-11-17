# A parte da cotação da renovação em "Ajustar renovações" (E8, #2901), que Carteira::Renovacao::Ajustes junta ao resto.
#
# Sem a chave da cotação na conta (Carteira::Cotacao::Liberada), o formato é o da E5, tudo desligado (`DESLIGADA`): a
# tela não muda e nada novo aparece. Com a chave:
# - `aggerLigado`: a conexão do Agger da conta está pronta (Carteira::Conector.ligado?, a mesma do resumo da carteira);
# - `cotaSozinha`: a conta tem o Agente de Cotação, e por isso pode escolher `robo` ou `lia` (sem ele, só `ninguem`);
# - `cotaSemConversa`: sempre false. A cotação roda na conversa do contato (decisão D5), nunca sem ela;
# - `agente`: o nome do Agente de Cotação da conta, ou nulo;
# - `cotacaoLiberada`: true (a tela mostra o cartão da cotação);
# - `caixas`: as caixas do WhatsApp oficial da conta (as únicas por onde o modelo sai), cada uma com `liaLigada`, para a
#   tela avisar antes quando a escolha é "Lia responde" e a Lia não está naquela caixa.
# As escolhas guardadas (`quemCota`, `quemEnvia`, `quemResponde`, `caixaId`) vão em `ajustes` (`guardados`).
class Carteira::Cotacao::Ajustes
  DESLIGADA = { aggerLigado: false, cotaSozinha: false, cotaSemConversa: false, agente: nil }.freeze

  def self.guardados(config)
    { quemCota: config.quem_cota, quemEnvia: config.quem_envia, quemResponde: config.quem_responde, caixaId: config.inbox_id }
  end

  def initialize(account, config)
    @account = account
    @config = config
  end

  def call
    return DESLIGADA unless Carteira::Cotacao::Liberada.para?(@account)

    agente = Carteira::Cotacao.agente(@account)
    { aggerLigado: Carteira::Conector.ligado?(@account), cotaSozinha: agente.present?, cotaSemConversa: false,
      agente: agente&.name, cotacaoLiberada: true, caixas: caixas(agente) }
  end

  private

  def caixas(agente)
    com_lia = agente ? Autonomia::Agents::AgentInbox.kept.where(autonomia_agent_id: agente.id).pluck(:inbox_id) : []
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id)
            .select { |caixa| Whatsapp::Templates::MetaClient.supported?(caixa) }
            .map { |caixa| { id: caixa.id, nome: caixa.name, liaLigada: com_lia.include?(caixa.id) } }
  end
end
