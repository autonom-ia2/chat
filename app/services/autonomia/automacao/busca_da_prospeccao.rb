# O "buscar" do passo "prospecção" (#2414 G21, #2706): roda a busca, espera a conferência de WhatsApp e cria os cards.
# Tudo pelas peças da tela da Prospecção, nada por caminho próprio:
#
# 1. Repete a busca do histórico (`busca_id`) com `quantas` empresas: o mesmo SearchRunner do "Repetir", com `fresh`
#    (sem cache, chama o provedor de novo), como quem ligou. O provedor é o da Prospecção da conta (Setting#provider):
#    o passo nunca escolhe o Google. Depois, o mesmo LeadWorkQueue.after_search da tela, que põe a conferência de
#    WhatsApp na fila. Sem sessão do WhatsApp para conferir (WhatsappVerifier.available_for?), para antes de pagar a
#    busca: ninguém seria conferido e o passo esperaria à toa.
# 2. Espera a conferência (`:esperar`): o executor guarda o passo e volta a cada INTERVALO. A busca da execução fica
#    marcada no metadata dela (`automacao`), e é por ela que a volta acha a busca, sem rodar outra. Passado o PRAZO (o
#    mesmo da Prospecção para dar a conferência por perdida), segue com quem já foi conferido e registra
#    `conferencia_no_prazo`, com quantas ficaram sem resposta.
# 3. Um card por empresa com WhatsApp (o do Google ou o do site, conferido), na etapa escolhida, pelo mesmo envio em lote
#    da tela (CrmCardBatch, de 30 em 30). Lead recusado ou descartado fica de fora. O card não tem etiqueta: as
#    etiquetas vão no contato de cada card criado agora (lote a lote), que é o público da campanha. Card que já existia
#    não ganha etiqueta: a empresa já foi prospectada. Busca que falhou depois de pagar o Google não se repete
#    (`busca_falhou_paga`), e sem a chave do Google para antes de tentar (`prospeccao_sem_chave_google`).
#
# Repetir a rodada não duplica nada: a busca da execução é achada pela marca, e o envio em lote devolve o card que já
# existe ("existing").
class Autonomia::Automacao::BuscaDaProspeccao
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  Prospecting = ::Autonomia::Prospecting
  INTERVALO = 2.minutes
  PRAZO = Prospecting::LeadWorkQueue::QUEUED_STALE_AFTER
  # O que a busca grava do pedido e o "Repetir" manda de novo (o `metadata` permitido no SearchesController#search_params).
  DO_PEDIDO = %w[location_place_id location_latitude location_longitude location_label sort_key score_mode scoring_profile_id
                 preset_id decision_maker_type advanced_filters filters].freeze
  # A conferência de cada número: o do Google (phone) e o do site (enriched_whatsapp).
  CONFERENCIAS = { phone: 'whatsapp_verification', enriched_whatsapp: 'site_whatsapp_verification' }.freeze
  CONFERINDO = [nil, 'queued', 'running'].freeze

  def initialize(execucao:, passo:, account_user:)
    @execucao = execucao
    @passo = passo
    @account_user = account_user
    @conta = execucao.account
  end

  def executar
    busca = da_execucao || buscar
    return busca if busca.is_a?(Resultado)

    leads = Prospecting::Lead.where(account: @conta, id: Array(busca.metadata['lead_ids'])).to_a
    sem_resposta = leads.select { |lead| conferindo?(lead) }
    return esperar(busca) if sem_resposta.any? && Time.current < busca.created_at + PRAZO

    etapa = @conta.crm_pipeline_stages.find_by(id: @passo['etapa_id'])
    return pulado('etapa_sumiu') if etapa.nil?

    criar_cards(busca, leads, sem_resposta, etapa)
  end

  private

  # Só a busca concluída: a que falhou (Google fora) não serve, e a nova tentativa roda outra.
  def da_execucao = da_execucao_em(Prospecting::Search.completed).order(:id).last

  def da_execucao_em(escopo)
    escopo.where(account: @conta)
          .where("metadata -> 'automacao' ->> 'execucao_id' = ?", @execucao.id.to_s)
          .where("metadata -> 'automacao' ->> 'passo' = ?", @passo['id'])
  end

  def buscar
    origem = ::Autonomia::Automacao::PassoDeProspeccao.busca(@conta, @account_user, @passo['busca_id'])
    impedimento = origem.nil? ? 'busca_sumiu' : impedimento_da_busca
    return permanente(impedimento) if impedimento

    resultado = Prospecting::SearchRunner.new(account: @conta, user: @account_user.user, params: pedido(origem)).perform
    conferir_whatsapp(resultado.leads)
    resultado.search
  rescue Prospecting::SearchRunner::ProviderError, Prospecting::SearchRunner::ScoreEngineError => e
    Rails.logger.info("[automacao][prospeccao] busca sem resposta execucao=#{@execucao.id} #{e.class}")
    Resultado.new(tipo: :passageiro, motivo: 'busca_sem_resposta', dados: {})
  rescue ActiveRecord::RecordInvalid, Prospecting::SearchRunner::UnsupportedProviderError => e
    Rails.logger.info("[automacao][prospeccao] busca recusada execucao=#{@execucao.id} #{e.class}")
    permanente('busca_recusada')
  end

  # O que impede a busca antes de pagar: sem WhatsApp para conferir, sem a chave do Google, ou a busca desta execução já
  # ficou no meio ou falhou depois de pagar.
  def impedimento_da_busca
    return 'prospeccao_sem_whatsapp' unless Prospecting::WhatsappVerifier.available_for?(@conta)
    return 'prospeccao_sem_chave_google' unless provedor_pronto?

    return 'busca_interrompida' if interrompida?

    'busca_falhou_paga' if falhou_paga?
  end

  # A busca desta execução que ficou no meio (o processo caiu durante a chamada ao Google: deploy, falta de memória). O
  # SearchRunner não chegou a gravar o status nem as chamadas pagas, então não dá para saber se pagou: para, sem repetir.
  def interrompida?
    da_execucao_em(Prospecting::Search.pending).exists?
  end

  # Sem a chave do Google o SearchRunner recusa antes de chamar (ProviderError): não é passageiro, tentar de novo não
  # resolve.
  def provedor_pronto?
    configuracao = Prospecting::Setting.for_account(@conta)
    configuracao.provider != 'google_places' || configuracao.google_places_configured?
  end

  # A busca desta execução que falhou depois de pagar chamadas ao Google: repetir pagaria de novo. Para, com o motivo.
  def falhou_paga?
    da_execucao_em(Prospecting::Search.failed).where('consumed_api_units > 0').exists?
  end

  # A busca já foi paga: a falha na fila da conferência fica no log, e o prazo segue com quem for conferido.
  def conferir_whatsapp(leads)
    Prospecting::LeadWorkQueue.after_search(account: @conta, leads: leads)
  rescue StandardError => e
    Rails.logger.error("[automacao][prospeccao] fila da conferência falhou execucao=#{@execucao.id} #{e.class}")
  end

  # O pedido do "Repetir" (raio pedido, não o que a expansão alcançou), com `quantas` e a marca da execução.
  def pedido(origem)
    metadata = origem.metadata.to_h
    { query: origem.query, location: origem.location, radius: metadata['requested_radius'] || origem.radius,
      area_type: origem.area_type, area_config: origem.area_config, categories: origem.categories,
      requested_limit: @passo['quantas'], fresh: true,
      metadata: metadata.slice(*DO_PEDIDO).merge('automacao' => { 'execucao_id' => @execucao.id, 'passo' => @passo['id'] }) }
  end

  def conferindo?(lead)
    CONFERENCIAS.any? { |campo, chave| lead.public_send(campo).present? && CONFERINDO.include?(status(lead, chave)) }
  end

  def escolhido?(lead) = com_whatsapp?(lead) && !lead.consent_refused? && !lead.discarded?

  def com_whatsapp?(lead) = CONFERENCIAS.values.any? { |chave| status(lead, chave) == 'verified' }

  def status(lead, chave) = lead.metadata.to_h.dig(chave, 'status')

  def esperar(busca)
    Resultado.new(tipo: :esperar, motivo: nil, dados: { 'ate' => [Time.current + INTERVALO, busca.created_at + PRAZO].min })
  end

  def criar_cards(busca, leads, sem_resposta, etapa)
    escolhidos = leads.select { |lead| escolhido?(lead) }
    envios = escolhidos.map(&:id).each_slice(Prospecting::CrmCardBatch::MAX_LEADS).map { |ids| enviar(ids, etapa) }
    contagem = { 'busca_id' => busca.id, 'empresas' => leads.size, 'com_whatsapp' => escolhidos.size, 'sem_resposta' => sem_resposta.size }
    Resultado.new(tipo: :ok, motivo: sem_resposta.any? ? 'conferencia_no_prazo' : nil, dados: contagem.merge(dos_envios(envios)))
  rescue ActiveRecord::RecordNotFound, Prospecting::CrmCardConverter::Error => e
    Rails.logger.info("[automacao][prospeccao] envio ao funil recusado execucao=#{@execucao.id} #{e.class}")
    permanente('etapa_fora_do_alcance')
  end

  def dos_envios(envios)
    { 'cards_criados' => envios.sum { |envio| envio.created.size }, 'ja_tinham_card' => envios.sum { |envio| envio.existing.size },
      'falharam' => envios.sum { |envio| envio.failed.size } }
  end

  # Cada lote ganha as etiquetas logo depois de enviado: se um lote seguinte falhar, os cards já criados ficam com elas.
  # Limite conhecido: se o processo cair entre o envio e a etiqueta, a volta acha os cards como "existing" e não etiqueta
  # (card que já existia é empresa já prospectada). Esses contatos ficam fora da campanha da etiqueta.
  def enviar(ids, etapa)
    envio = Prospecting::CrmCardBatch.new(account: @conta, user: @account_user.user, lead_ids: ids, pipeline_id: etapa.pipeline_id,
                                          stage_id: etapa.id, leads_scope: Prospecting::Visibility.new(@account_user).leads(
                                            Prospecting::Lead.where(account: @conta)
                                          )).perform
    etiquetar(envio)
    envio
  end

  # O contato de cada card criado agora (contato novo ou o que a conta já tinha com o mesmo número): o card que já
  # existia é empresa já prospectada.
  def etiquetar(envio)
    titulos = @conta.labels.where(id: @passo['etiquetas']).pluck(:title)
    return if titulos.empty?

    contatos = envio.created.filter_map { |item| item[:contact_id] }
    @conta.contacts.where(id: contatos).find_each { |contato| contato.add_labels(titulos) }
  end

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})

  def permanente(motivo) = Resultado.new(tipo: :permanente, motivo: motivo, dados: {})
end
