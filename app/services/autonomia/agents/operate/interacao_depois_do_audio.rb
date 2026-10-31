# A INTERAÇÃO DA RESPOSTA EM VOZ SAI DEPOIS DO ÁUDIO (#1479). O áudio vai com anexo, e o `Message#send_reply` o manda
# por `SendReplyJob.set(wait: 2.seconds)`; a interação (opções, link, pedido de localização) postada logo depois, sem
# anexo, saía na hora e chegava ao cliente ANTES do áudio. Agora ela segue o caminho dos cartões (`CartoesDoTurno`, F3):
# fica gravada no áudio, a âncora (`autonomia_interacao_depois`), e o `EnviarCartoesJob` a posta quando o áudio saiu para
# o canal (`SaidaDaMensagem`), antes dos cartões. Só na voz: no clássico ela vai na própria mensagem de texto, nos
# pedaços no último pedaço, e a síntese que falha cai no texto com a interação junto.
#
# O ÁUDIO GRAVA A MENSAGEM JÁ MONTADA (`Interacao.mensagem` sem texto antes: o corpo, o `rich_message` e a versão em
# texto), a marca do pedido de localização (`PedidoDeLocalizacao.marca`) e o token (o turno + `interacao`). Na hora de
# postar, a regra da caixa (`Interacao.sai_o_formato?`) decide de novo, como no cartão: sem o formato, sai a versão em
# texto. Os destinatários do e-mail (#1828) também são calculados na hora (`Crm::Email::Destinatarios.da_ia`), nunca
# gravados no áudio. A mensagem leva o que a de antes levava (`autonomia_agent_id` e `autonomia_reply_to_message_id` do
# áudio, o robô do áudio): `Interacao.oferta_do_agente?`, o toque (`selected_option` com `in_reply_to`) e a
# `LocalizacaoRecebida` a reconhecem igual.
#
# Sob o lock da conversa, nada sai (motivo para o registro, só ids):
#   - `pessoa_respondeu`: uma pessoa da equipe escreveu depois do áudio;
#   - `desligado`: a interação não está mais ligada na conta (`ligada?`, o mesmo gate que o Responder usa para procurar
#     a âncora no retry). Não é o `Interacao.disponivel?` inteiro: ele depende do contexto de entrega, que o job não tem;
#   - `dono_mudou`: o vínculo do robô do áudio não responde mais a conversa (`Operate.no_comando?`, o contrato do
#     ChunkedDeliveryJob: sem responsável humano, agente ativo, mesma caixa);
#   - `turno_superado`: o robô do áudio já respondeu outra mensagem do cliente depois dele (id maior que o do áudio e
#     `autonomia_reply_to_message_id` presente e diferente). Só ids e o campo; o texto nunca é lido.
# O token, conferido sob o mesmo lock, impede a interação duplicada (dois jobs do mesmo áudio, o retry do turno que
# reenfileira para o áudio existente).
class Autonomia::Agents::Operate::InteracaoDepoisDoAudio
  NA_ANCORA = 'autonomia_interacao_depois'.freeze
  TOKEN = 'autonomia_interacao_token'.freeze
  RESPOSTA = 'autonomia_reply_to_message_id'.freeze

  class << self
    # A interação para o áudio gravar. {} sem interação: o áudio fica como sempre.
    def marca(interacao, turno:, conversation:)
      return {} if interacao.nil?

      final = ::Autonomia::Agents::Interacao.mensagem(interacao, texto: nil, conversation: conversation)
      { NA_ANCORA => { 'content' => final[:content], 'rich_message' => final[:rich_message], 'em_texto' => final[:em_texto],
                       'marca' => ::Autonomia::Agents::Interacao::PedidoDeLocalizacao.marca(interacao),
                       'token' => "#{turno}:interacao" } }
    end

    # A interação gravada na mensagem, ou nil.
    def da_ancora(message)
      pendente = message&.content_attributes.to_h[NA_ANCORA]
      pendente if pendente.is_a?(Hash) && pendente['token'].present?
    end

    # A conta pode ter a interação depois do áudio: a Fase 2 (as opções e o link só existem com ela).
    def ligada?(account)
      ::Autonomia::Agents::Fase2.ligada?(account)
    end
  end

  def initialize(ancora)
    @ancora = ancora
    @conversation = ancora.conversation
  end

  def pendente
    @pendente ||= self.class.da_ancora(@ancora)
  end

  def pendente?
    pendente.present?
  end

  # A mensagem da interação já postada, ou nil.
  def postada
    return if pendente.nil?

    @conversation.messages.outgoing.where(sender_type: 'AgentBot')
                 .where('content_attributes::text LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(pendente['token'])}%")
                 .find { |message| message.content_attributes.to_h[TOKEN].to_s == pendente['token'] }
  end

  # Posta a interação sob o lock da conversa, conferindo de novo que ela não saiu e as guardas acima. -> nil quando postou
  # (ou outro job já a postou); senão o motivo de não postar. Erro sobe para quem chama.
  def postar!
    @conversation.with_lock do
      motivo = motivo_para_nao_postar
      construir! unless motivo || postada
      motivo
    end
  end

  private

  def motivo_para_nao_postar
    return 'pessoa_respondeu' if ::Autonomia::Agents::Operate::PessoaDaEquipe.respondeu_depois?(@conversation, @ancora.id)
    return 'desligado' unless self.class.ligada?(@conversation.account)
    return 'dono_mudou' unless ::Autonomia::Agents::Operate.no_comando?(@conversation, vinculo)

    'turno_superado' if turno_superado?
  end

  # O vínculo do robô que postou o áudio, na caixa atual da conversa.
  def vinculo
    ::Autonomia::Agents::AgentInbox.kept.find_by(inbox_id: @conversation.inbox_id, agent_bot_id: @ancora.sender_id)
  end

  def turno_superado?
    deste_turno = @ancora.content_attributes.to_h[RESPOSTA].to_s
    @conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: @ancora.sender_id).where('id > ?', @ancora.id)
                 .any? do |message|
                   outro = message.content_attributes.to_h[RESPOSTA].to_s
                   outro.present? && outro != deste_turno
                 end
  end

  def construir!
    content, formato = conteudo_e_formato
    do_audio = @ancora.content_attributes.to_h.slice('autonomia_agent_id', RESPOSTA)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: content, message_type: 'outgoing', sender_type: 'AgentBot', sender_id: @ancora.sender_id, private: false,
        content_attributes: do_audio.merge(formato, pendente['marca'].to_h, TOKEN => pendente['token']),
        **::Crm::Email::Destinatarios.da_ia(@conversation)
      )
    ).perform
  end

  # -> [o conteúdo, as chaves do formato]. Sem o formato (a caixa não o leva agora): a versão em texto, sem chave.
  def conteudo_e_formato
    formato = pendente['rich_message']
    if formato.is_a?(Hash) && ::Autonomia::Agents::Interacao.sai_o_formato?(formato, pendente['content'].to_s, @conversation)
      return [pendente['content'], { RichMessages::KEY => formato }]
    end

    [pendente['em_texto'], {}]
  end
end
