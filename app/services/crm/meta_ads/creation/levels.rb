# Os três níveis de um anúncio criado aqui (#2198): campanha, grupo e anúncio. Tudo nasce PAUSADO (decisão do Rodrigo,
# opção a, 27/10) e só a pessoa liga, no "Ativar anúncio".
#
# - `ensure_paused!`: depois de criar, relê os três; o que não vier PAUSED é pausado na hora e fica na Auditoria
#   (`meta_ads_create_repaused`). Sem conseguir pausar, erro: o criar desfaz tudo. Devolve o que releu, e o criar diz
#   por ele se o anúncio já está em análise da Meta (#2354).
# - `activate!`: liga campanha, grupo e anúncio, nesta ordem, relendo cada um. Se um falhar, volta os já ligados para
#   PAUSED e sobe o erro. Se nem voltar der, `meta_partial` com os ids que ficaram ligados, e a Auditoria registra
#   (`meta_ads_activate_partial`). Se a Meta ligou os três e só a gravação local falhar, é sucesso: o erro vai para o
#   rastreador.
# - `pause!`: pausa anúncio, grupo e campanha, nesta ordem (simétrico ao ativar), relendo cada um. Se um falhar, sobe o
#   erro (`pause_partial` quando algum já tinha pausado) e a Auditoria registra o que pode ter ficado ligado
#   (`meta_ads_pause_partial`). Nada é religado.
class Crm::MetaAds::Creation::Levels
  COLUMNS = { 'campaign' => :campaign_id, 'adset' => :adset_id, 'ad' => :ad_id }.freeze
  REPAUSED_ACTION = 'meta_ads_create_repaused'.freeze
  PARTIAL_ACTION = 'meta_ads_activate_partial'.freeze
  PAUSE_PARTIAL_ACTION = 'meta_ads_pause_partial'.freeze

  def initialize(client, account:, user:)
    @client = client
    @account = account
    @user = user
  end

  # Devolve como cada nível ficou ({ 'ad' => { 'status', 'effective_status' }, … }; {} quando não leu). Nível pausado
  # na hora é relido de novo: a situação de entrega depois de pausar é outra.
  def ensure_paused!(record)
    COLUMNS.to_h do |level, column|
      id = record.public_send(column)
      reread = @client.object_status(id)
      unless reread.ok && reread.data['status'] == 'PAUSED'
        repause!(level, id, reread)
        reread = @client.object_status(id)
      end
      [level, reread.ok ? reread.data : {}]
    end
  end

  def activate!(record)
    turned = []
    COLUMNS.each do |level, column|
      id = record.public_send(column)
      failure = turn_on(id)
      # O nível que falhou também volta: a Meta pode ter ligado e só a releitura ter falhado.
      raise revert!(turned + [[level, id]], failure) if failure

      turned << [level, id]
    end
    mark_activated(record)
  end

  def pause!(record)
    levels = COLUMNS.to_a.reverse.map { |level, column| [level, record.public_send(column)] }
    levels.each_with_index do |(_level, id), index|
      failure = switch(id, 'PAUSED')
      next unless failure

      audit!(PAUSE_PARTIAL_ACTION, 'active' => levels.drop(index).to_h)
      # Já pausou algum nível: a tela diz que parte pode ter ficado ligada. No primeiro, nada mudou: o erro da Meta.
      raise Crm::MetaAds::AdManagement::Error, index.zero? ? failure : 'pause_partial'
    end
  end

  private

  def repause!(level, id, reread)
    result = @client.update_object(id, status: 'PAUSED')
    audit!(REPAUSED_ACTION, 'level' => level, 'object_id' => id, 'paused' => result.ok,
                            'status' => reread.ok ? reread.data['status'] : 'unread')
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
  end

  def mark_activated(record)
    record.update!(activated_at: Time.current)
  rescue ActiveRecord::ActiveRecordError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  def turn_on(id)
    switch(id, 'ACTIVE')
  end

  # nil quando mudou e a releitura confirma a situação nova; senão, o código do erro.
  def switch(id, status)
    result = @client.update_object(id, status: status)
    return code_of(result) unless result.ok

    reread = @client.object_status(id)
    return code_of(reread) unless reread.ok

    'meta_refused' unless reread.data['status'] == status
  end

  def code_of(result)
    result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  # Volta para PAUSED o que já foi ligado, do último para o primeiro.
  def revert!(turned, code)
    left = turned.reverse.reject { |_level, id| @client.update_object(id, status: 'PAUSED').ok }
    return Crm::MetaAds::AdManagement::Error.new(code) if left.empty?

    audit!(PARTIAL_ACTION, 'active' => left.to_h)
    Crm::MetaAds::AdManagement::Error.new('meta_partial')
  end

  # Falha ao gravar a Auditoria vai para o rastreador: a Meta já mudou, e a resposta diz a verdade.
  def audit!(action, changes)
    Audited.audit_class.create!(auditable: @account, user: @user, action: action, audited_changes: changes)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end
end
