# Leva o aviso do Guia a quem deve recebê-lo (#935).
#
# - Só administradores (ou os da `para_quem` da vigia que forem administradores). Agente comum: nada.
# - Um aviso por pessoa por pulso, juntando tudo o que cruzou: dez vigias juntas são um aviso só.
# - A `chave` é única: o mesmo aviso nunca nasce duas vezes.
# - Orçamento: 3 avisos por pessoa por dia. O excedente fica `adiado` e sai num resumo no dia seguinte.
#   O urgente não espera: conexão caída não pode esperar o dia seguinte (D5).
# - O aviso vira um turno da conversa da pessoa com o Guia, e a tela recebe pelo ActionCable.
# - O urgente também vira notificação (`guide_alert`): sino, push e e-mail que já existem.
class Autonomia::Guide::Entrega
  ORCAMENTO_DIARIO = 3
  EVENTO = 'guide.aviso.created'.freeze
  AVISO = Autonomia::Guide::Aviso

  def initialize(account, agora: Time.current)
    @account = account
    @agora = agora
    @texto = Autonomia::Guide::TextoDoAviso.new(account)
  end

  # `sinais`: [{ vigia:, valor:, media:, item_id: }] — o que cruzou o gatilho neste pulso.
  def avisar!(sinais, veredito)
    por_pessoa(sinais).each do |user, deles|
      chave = "pulso:#{user.id}:#{Digest::SHA256.hexdigest(deles.map { |sinal| marca(sinal) }.sort.join(','))}"
      entregar(user, chave: chave, gravidade: veredito.gravidade, sinal: { 'sinais' => deles.map { |sinal| sinal_de(sinal) } },
                     texto: @texto.do_pulso(deles, mesmo_assunto: veredito.mesmo_assunto))
    end
  end

  # A vigia de quem perdeu o administrador foi pausada: os outros administradores ficam sabendo.
  def pausada!(vigia)
    administradores.where.not(id: vigia.criado_por_id).find_each do |user|
      entregar(user, chave: "pausada:#{user.id}:#{vigia.id}:#{vigia.updated_at.to_i}", gravidade: 'agir',
                     sinal: { 'vigia_id' => vigia.id }, texto: @texto.pausada(vigia))
    end
  end

  # O WhatsApp API (sessão auxiliar do WhatsApp Híbrido, chat#1067) caiu: urgente, para todos os administradores.
  # `chave` leva o instante da queda: uma queda é um aviso só, mesmo com vários eventos do motor.
  def whatsapp_api_caiu!(inbox, caiu_em)
    administradores.find_each do |user|
      entregar(user, chave: "whatsapp_api:#{user.id}:#{inbox.id}:#{caiu_em.to_i}", gravidade: AVISO::URGENTE,
                     sinal: { 'inbox_id' => inbox.id }, texto: @texto.whatsapp_api_caiu(inbox))
    end
  end

  # O WhatsApp avisou que o número está perto (ou no) limite de conversas novas (chat#1067).
  # Uma vez por estado e ciclo; urgente só no bloqueio.
  def whatsapp_api_limite!(inbox, estado, inicio_ciclo, fim_ciclo)
    gravidade = estado == 'CAPPED' ? AVISO::URGENTE : 'agir'
    administradores.find_each do |user|
      entregar(user, chave: "whatsapp_api_limite:#{user.id}:#{inbox.id}:#{estado}:#{inicio_ciclo}", gravidade: gravidade,
                     sinal: { 'inbox_id' => inbox.id }, texto: @texto.whatsapp_api_limite(inbox, estado, fim_ciclo))
    end
  end

  # O resumo dos adiados de dias anteriores: um por pessoa, no primeiro pulso do dia.
  def resumir_adiados!
    adiados = AVISO.where(account: @account, estado: AVISO::ADIADO).where(created_at: ...@agora.beginning_of_day).includes(:user)
    adiados.group_by(&:user).each do |user, lista|
      aviso = entregar(user, chave: "resumo:#{user.id}:#{@agora.to_date.iso8601}", gravidade: 'info',
                             sinal: { 'avisos' => lista.map(&:id) }, texto: @texto.resumo(lista))
      AVISO.where(id: lista.map(&:id)).update_all(estado: AVISO::RESUMIDO, updated_at: @agora) if aviso # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def administradores
    @account.administrators
  end

  def por_pessoa(sinais)
    admins = administradores.to_a
    sinais.each_with_object(Hash.new { |hash, chave| hash[chave] = [] }) do |sinal, grupos|
      para_quem = Array(sinal[:vigia].para_quem)
      admins.each { |user| grupos[user] << sinal if para_quem.empty? || para_quem.include?(user.id) }
    end
  end

  def marca(sinal)
    "#{sinal[:vigia].id}@#{sinal[:vigia].janela(@agora)}"
  end

  def sinal_de(sinal)
    { 'vigia_id' => sinal[:vigia].id, 'valor' => sinal[:valor], 'media' => sinal[:media], 'item_id' => sinal[:item_id] }.compact
  end

  # nil quando o aviso já existia (a chave é única).
  def entregar(user, chave:, gravidade:, sinal:, texto:)
    urgente = gravidade == AVISO::URGENTE
    estado = !urgente && entregues_hoje(user) >= ORCAMENTO_DIARIO ? AVISO::ADIADO : AVISO::NOVO
    aviso = AVISO.create!(account: @account, user: user, chave: chave, estado: estado, gravidade: gravidade, sinal: sinal,
                          texto: texto, created_at: @agora)
    return aviso if aviso.estado == AVISO::ADIADO

    na_conversa!(aviso)
    notificar!(aviso) if urgente
    aviso
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    Rails.logger.info("[autonomia][guide][entrega] account=#{@account.id} user=#{user.id} repetido #{e.class}")
    nil
  end

  def entregues_hoje(user)
    AVISO.where(account: @account, user: user, created_at: @agora.all_day).where.not(turno_id: nil).count
  end

  # O aviso entra na conversa mais recente da pessoa com o Guia; sem nenhuma, abre uma.
  def na_conversa!(aviso)
    conversa = Autonomia::Guide::Conversa.de(@account, aviso.user).recentes.first ||
               Autonomia::Guide::Conversa.create!(account: @account, user: aviso.user,
                                                  titulo: Autonomia::Guide::Conversa.titulo_para(aviso.texto))
    aviso.update!(turno: Autonomia::Guide::Turno.do_aviso(conversa, aviso))
    ActionCableBroadcastJob.perform_later([aviso.user.pubsub_token], EVENTO,
                                          { account_id: @account.id, id: aviso.id, gravidade: aviso.gravidade })
  end

  def notificar!(aviso)
    Notification.create!(notification_type: :guide_alert, user: aviso.user, account: @account, primary_actor: aviso)
  end
end
