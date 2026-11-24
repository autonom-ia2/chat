# #3099 (F3 do épico #3095): duas versões da mensagem na campanha com público. Desenho em docs/3099-desenho/desenho.md.
#
# Uma parte do público (o teste) recebe a mensagem: cada versão para um pedaço. Depois da espera, o resto recebe a
# melhor (CampaignJourney::DuasVersoes::Escolha, pelo cron) ou a que a pessoa escolher. O teste tem pelo menos
# MINIMO_POR_VERSAO pessoas na versão que recebe menos, ou PARTE_DO_TESTE% do público, o que for maior. Se sobra pouco
# para o resto (menos de MINIMO_NO_RESTO), não vale esperar: todo mundo recebe uma das duas (estado 'todos') e o
# resultado só compara. As mesmas constantes e a mesma conta estão na tela (CampaignJourney/duasVersoes.js); um spec de
# contrato compara as duas.
#
# O sorteio é fixo, como o do grupo de controle (CampaignJourney::GrupoDeControle): ordena as pessoas pelo hash de
# "versoes:link:contato" (outro sal, para não depender da ordem do grupo) e reparte. O grupo de controle sai antes: o
# público do teste é o "Vão receber" sem o grupo. Quem caiu em qual versão fica em campaign_version_contacts.
#
# Enquanto o resto espera ('testando' ou 'esperando_voce'), só quem tem versão recebe (#so_quem_recebe_agora, usado por
# AudienceContacts.contacts_for e pela fila do e-mail). Na escolha (#mandar_resto!), o resto ganha a versão escolhida
# e o envio sai pelo mesmo caminho do envio original (CampaignJourney::DuasVersoes::EnvioDoResto).
#
# D4 (#3101, F5 "melhor horário"): o teste sai no horário da campanha; o resto, no melhor horário de cada pessoa. O ponto
# de extensão da F5 é Autonomia::RitmoDeEnvio::Porteiro, consultado antes de cada envio em todos os canais: lá ela
# adia a pessoa para o melhor horário, e pula quem está no teste (#fase_de devolve 'teste').
class CampaignJourney::DuasVersoes
  class Invalida < StandardError
    attr_reader :code, :details

    def initialize(code, details = nil)
      @code = code
      @details = details
      super(code)
    end
  end

  CRITERIOS = %w[respostas compras eu_escolho].freeze
  DIVISOES = [50, 70].freeze
  ESPERAS = [2, 4, 24].freeze
  ESPERA_POR_CRITERIO = { 'respostas' => 4, 'compras' => 24, 'eu_escolho' => 4 }.freeze
  VERSOES = [1, 2].freeze
  MINIMO_POR_VERSAO = 100
  PARTE_DO_TESTE = 20
  MINIMO_NO_RESTO = 100
  ESTADOS = %w[testando esperando_voce escolhida todos].freeze
  ESPERANDO_O_RESTO = %w[testando esperando_voce].freeze
  # 'sem_envio': ninguém do teste recebeu até PRAZO_SEM_ENVIO (CampaignJourney::DuasVersoes::SemEnvio).
  ESCOLHIDA_POR = %w[sistema voce empate sem_envio].freeze
  # D5: no "eu escolho", sem ninguém escolher, a versão 1 vai sozinha para o resto depois deste prazo.
  PRAZO_DO_EU_ESCOLHO = 3.days
  # Ninguém do teste recebeu (todos pulados, canal desligado, falta de variável): o resto não espera para sempre.
  PRAZO_SEM_ENVIO = 3.days

  # `params`: { criterio, divisao, espera_horas } da tela. nil (ou vazio) = sem duas versões. Valor fora das opções vai
  # para a validação do link (RecordInvalid).
  def self.regra(params)
    dados = params.to_h.with_indifferent_access
    return if dados.blank?

    criterio = dados[:criterio].presence&.to_s || 'respostas'
    espera = dados[:espera_horas].presence || ESPERA_POR_CRITERIO.fetch(criterio, 4)
    { teste_criterio: criterio, teste_divisao: (dados[:divisao].presence || 50).to_i, teste_espera_horas: espera.to_i }
  end

  # A regra conferida: "mais compras" só conta com o CRM ligado (a mesma recusa da automação,
  # Autonomia::Automacao::DuasVersoes#problemas_ao_salvar). Sem o CRM, as compras dariam zero nas duas e o empate
  # mandaria a versão 1 sem ninguém saber por quê.
  def self.conferir!(params)
    regra = regra(params)
    raise Invalida, 'criterio_sem_compras' if regra && regra[:teste_criterio] == 'compras' && !Crm::Config.enabled?

    regra
  end

  # O plano do teste para `publico` pessoas (já sem o grupo de controle), igual a planoDoTeste da tela.
  def self.plano(publico, divisao = 50)
    total = [publico.to_i, 0].max
    menor_parte = 100 - [divisao, 100 - divisao].max
    minimo = ((MINIMO_POR_VERSAO * 100) + menor_parte - 1) / menor_parte
    teste = [minimo, ((total * PARTE_DO_TESTE) + 99) / 100].max
    if total - teste < MINIMO_NO_RESTO
      return { modo: 'todos', teste: total, **dividir(total, divisao), resto: 0, pequeno: total < minimo, minimo: minimo }
    end

    { modo: 'teste', teste: teste, **dividir(teste, divisao), resto: total - teste, pequeno: false, minimo: minimo }
  end

  def self.dividir(total, divisao)
    versao1 = Rational(total * divisao, 100).round
    { versao1: versao1, versao2: total - versao1 }
  end

  def self.para(campaign)
    new(CampaignAudienceLink.for_campaign(campaign))
  end

  attr_reader :link

  def initialize(link)
    @link = link
  end

  def ativo?
    @link.present? && @link.teste_criterio.present?
  end

  def esperando_o_resto?
    ativo? && ESPERANDO_O_RESTO.include?(@link.teste_estado)
  end

  def segunda
    @link&.segunda_versao.to_h
  end

  # Grava a regra e a versão 2 (ou desliga as duas versões). Antes do envio: o sorteio antigo sai e o novo vale.
  def configurar!(params, segunda_versao)
    regra = self.class.conferir!(params)
    apagar!
    return desligar! if regra.nil?

    @link.update!(regra.merge(segunda_versao: segunda_versao.to_h, teste_estado: nil, teste_resto: 0, teste_escolhe_em: nil,
                              teste_vencedora: nil, teste_escolhida_por: nil, teste_escolhida_por_user_id: nil,
                              teste_escolhida_em: nil))
  end

  # `contact_ids`: quem vai receber, já sem o grupo de controle.
  def sortear!(contact_ids)
    return unless ativo?

    ordem = contact_ids.compact.uniq.sort_by { |id| posicao(id) }
    plano = self.class.plano(ordem.size, @link.teste_divisao)
    teste = ordem.first(plano[:teste])
    gravar(teste.first(plano[:versao1]), 1, 'teste')
    gravar(teste.drop(plano[:versao1]), 2, 'teste')
    @versoes_do_teste = nil
    @link.update!(teste_estado: plano[:modo] == 'todos' ? 'todos' : 'testando', teste_resto: plano[:resto])
  end

  # `relacao`: contatos (coluna :id) ou destinatários (coluna :contact_id). Enquanto o resto espera, só quem tem versão.
  def so_quem_recebe_agora(relacao, coluna: :id)
    return relacao unless esperando_o_resto?

    relacao.where(coluna => linhas.select(:contact_id))
  end

  # 1 ou 2. Quem está no teste tem a sua; o resto (e quem entrou no público depois do sorteio) recebe a escolhida, ou a
  # versão 1 enquanto não há escolhida. As linhas do resto têm sempre a escolhida (#gravar_resto), por isso basta o mapa
  # do teste, lido uma vez: o envio pergunta por pessoa, e uma consulta por pessoa pesava no caminho do envio.
  def versao_de(contact_id)
    return 1 unless ativo?

    versoes_do_teste[contact_id] || vencedora || 1
  end

  def versao_2?(contact_id)
    versao_de(contact_id) == 2
  end

  # 'teste', 'resto' ou nil. Para a F5 (D4): quem está no teste não vai para o melhor horário.
  def fase_de(contact_id)
    return unless ativo?

    linhas.where(contact_id: contact_id).pick(:fase)
  end

  def esperar_voce!
    @link.with_lock { @link.update!(teste_estado: 'esperando_voce') if @link.teste_estado == 'testando' }
  end

  # Escolhe a versão do resto e manda. Uma vez só: depois de escolhida (ou no público pequeno) devolve false e não muda
  # nada. `por`: :sistema, :voce ou :empate.
  def mandar_resto!(versao, por:, user: nil)
    escolheu = @link.with_lock do
      next false unless esperando_o_resto?

      @link.update!(teste_estado: 'escolhida', teste_vencedora: versao, teste_escolhida_por: por.to_s,
                    teste_escolhida_por_user_id: user&.id, teste_escolhida_em: Time.current)
      @link.update!(teste_resto: gravar_resto(versao))
      true
    end
    ActiveRecord.after_all_transactions_commit { CampaignJourney::EnviarRestoJob.perform_later(@link.id) } if escolheu
    escolheu
  end

  private

  # Sempre do banco (como o grupo de controle): a associação carregada ficaria vazia depois de um delete_all.
  def linhas
    CampaignVersionContact.where(campaign_audience_link_id: @link.id)
  end

  def apagar!
    linhas.delete_all
    @versoes_do_teste = nil
  end

  # { contact_id => versão } de quem está no teste: do tamanho do teste (20% do público, ou o público pequeno inteiro).
  def versoes_do_teste
    @versoes_do_teste ||= linhas.where(fase: 'teste').pluck(:contact_id, :versao).to_h
  end

  # A escolhida, relida do banco enquanto não houver: a escolha pode chegar com este objeto em uso por um envio longo.
  def vencedora
    @vencedora ||= @link.teste_vencedora || CampaignAudienceLink.where(id: @link.id).pick(:teste_vencedora)
  end

  def desligar!
    @link.update!(teste_criterio: nil, teste_estado: nil, teste_resto: 0, teste_escolhe_em: nil, segunda_versao: {})
  end

  def posicao(contact_id)
    Digest::SHA256.hexdigest("versoes:#{@link.id}:#{contact_id}")
  end

  # Quem ainda não tem versão vira 'resto' com a escolhida. Roda com o estado já 'escolhida': o público não é mais
  # filtrado. E-mail: os destinatários que já estão na lista (sincronizada antes do primeiro envio).
  def gravar_resto(versao)
    sem_versao = publico_atual.where.not(id: linhas.select(:contact_id))
    total = 0
    sem_versao.in_batches(of: CampaignJourney::RecipientTracking::INSERT_BATCH_SIZE) do |lote|
      ids = lote.pluck(:id)
      gravar(ids, versao, 'resto')
      total += ids.size
    end
    total
  end

  def publico_atual
    campaign = @link.campaign
    case campaign
    when EmailCampaign
      @link.account.contacts.where(id: campaign.email_campaign_recipients.where.not(contact_id: nil).select(:contact_id))
    when WhatsappApiCampaign then CampaignJourney::AudienceContacts.contacts_for(@link, channel: :whatsapp)
    else CampaignJourney::AudienceContacts.contacts_for(@link, channel: canal_do(campaign))
    end
  end

  def canal_do(campaign)
    CampaignJourney::ResultFinder.channel_of(campaign) == CampaignJourney::ResultFinder::SMS ? :sms : :whatsapp
  end

  def gravar(contact_ids, versao, fase)
    return if contact_ids.empty?

    agora = Time.current
    registros = contact_ids.map do |id|
      { account_id: @link.account_id, campaign_audience_link_id: @link.id, contact_id: id, versao: versao, fase: fase, created_at: agora }
    end
    CampaignVersionContact.insert_all(registros, unique_by: :idx_campaign_version_contacts_link_contact) # rubocop:disable Rails/SkipsModelValidations
  end
end
