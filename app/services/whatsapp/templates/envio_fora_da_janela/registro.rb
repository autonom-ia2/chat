# Grava o registro append-only de um envio fora da janela (#1585, tabela `whatsapp_out_of_window_sends`). Quem chama é o
# Followup IA, numa linha, DEPOIS que o `MessageSender` devolve `:sent`, com a mensagem criada e o
# `envio_fora_da_janela` do metadata que o `enviar` devolveu (mais `crm_follow_up_id` e `motivo`, opcionais).
# - Idempotente por mensagem: a mesma mensagem não grava duas vezes (índice único de message_id cobre a corrida).
# - Nunca levanta para quem chama: a mensagem já saiu, e o registro não pode virar falha de envio. Em erro, log e alerta
#   no rastreador de erros só com a classe e os ids (sem a mensagem do erro, que pode trazer dado do cliente), e devolve nil.
class Whatsapp::Templates::EnvioForaDaJanela::Registro
  LOG = '[whatsapp][templates][fora_da_janela] registro_falhou'.freeze
  # O que vai ao rastreador de erros: só ids e a classe do erro original, nunca a mensagem dele.
  Falhou = Class.new(StandardError)

  def self.call(message:, registro:)
    new(message: message, registro: registro).call
  end

  def initialize(message:, registro:)
    @message = message
    @bruto = registro
  end

  # -> WhatsappOutOfWindowSend (o novo ou o já gravado para a mensagem) | nil
  def call
    raise ArgumentError, 'mensagem_nao_gravada' unless @message.is_a?(Message) && @message.persisted?

    gravar
  rescue StandardError => e
    avisar(e)
    nil
  end

  private

  # Log e alerta (ChatwootExceptionTracker) com a mesma linha: ids e classe. Registro perdido é prova perdida; sem fila de
  # nova tentativa (decisão de 15/10/2026), o alerta é o que avisa alguém.
  def avisar(erro)
    linha = "#{LOG} account_id=#{@message.try(:account_id)} message_id=#{@message.try(:id)} #{erro.class.name}"
    Rails.logger.error(linha)
    ChatwootExceptionTracker.new(Falhou.new(linha)).capture_exception
  end

  # Savepoint: quem chama pode estar numa transação, e um comando recusado no Postgres a invalidaria inteira. Na corrida
  # (outra gravação da mesma mensagem entre a busca e o INSERT), o índice único recusa e vale a linha que ganhou.
  def gravar
    WhatsappOutOfWindowSend.transaction(requires_new: true) do
      WhatsappOutOfWindowSend.find_by(message_id: @message.id) || WhatsappOutOfWindowSend.create!(atributos)
    end
  rescue ActiveRecord::RecordNotUnique
    WhatsappOutOfWindowSend.find_by!(message_id: @message.id)
  end

  def registro
    @registro ||= @bruto.to_h.stringify_keys
  end

  def atributos
    {
      account_id: @message.account_id, inbox_id: @message.inbox_id, message: @message,
      crm_follow_up_id: registro['crm_follow_up_id'], whatsapp_template_consent_id: registro['consentimento_id'],
      tipo: registro['tipo'], caminho: registro['caminho'], escolha: registro['escolha'],
      template_name: registro['modelo'], template_language: registro['idioma'], categoria: registro['categoria'],
      origem: registro['origem'], motivo: registro['motivo']
    }
  end
end
