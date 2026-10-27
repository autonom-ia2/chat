# Os três níveis de um anúncio criado aqui (#2198): campanha, grupo e anúncio. Tudo nasce PAUSADO (decisão do Rodrigo,
# opção a, 27/10) e só a pessoa liga, no "Ativar anúncio".
#
# - `ensure_paused!`: depois de criar, relê os três; o que não vier PAUSED é pausado na hora e fica na Auditoria
#   (`meta_ads_create_repaused`). Sem conseguir pausar, erro: o criar desfaz tudo.
# - `activate!`: liga campanha, grupo e anúncio, nesta ordem, relendo cada um. Se um falhar, volta os já ligados para
#   PAUSED e sobe o erro. Se nem voltar der, `meta_partial` com os ids que ficaram ligados, e a Auditoria registra
#   (`meta_ads_activate_partial`).
class Crm::MetaAds::Creation::Levels
  COLUMNS = { 'campaign' => :campaign_id, 'adset' => :adset_id, 'ad' => :ad_id }.freeze
  REPAUSED_ACTION = 'meta_ads_create_repaused'.freeze
  PARTIAL_ACTION = 'meta_ads_activate_partial'.freeze

  def initialize(client, account:, user:)
    @client = client
    @account = account
    @user = user
  end

  def ensure_paused!(record)
    COLUMNS.each do |level, column|
      id = record.public_send(column)
      reread = @client.object_status(id)
      next if reread.ok && reread.data['status'] == 'PAUSED'

      result = @client.update_object(id, status: 'PAUSED')
      audit!(REPAUSED_ACTION, 'level' => level, 'object_id' => id, 'paused' => result.ok,
                              'status' => reread.ok ? reread.data['status'] : 'unread')
      raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
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
    record.update!(activated_at: Time.current)
  end

  private

  # nil quando ligou e a releitura confirma ACTIVE; senão, o código do erro.
  def turn_on(id)
    result = @client.update_object(id, status: 'ACTIVE')
    return code_of(result) unless result.ok

    reread = @client.object_status(id)
    return code_of(reread) unless reread.ok

    'meta_refused' unless reread.data['status'] == 'ACTIVE'
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
