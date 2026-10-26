# Mensagem que SAI pela conversa mas não é alguém respondendo nela (#2202): não diz que alguém leu a conversa, então
# não apaga a bolinha de não lida (ConversaCanal::VistaAoResponder). A lista é uma só, aqui:
# - envio automático em nome de alguém e campanha: as marcas de Autonomia::Agents::Operate::PessoaDaEquipe
#   (automação, follow-up, convite e aviso do Agendamento, campaign_id, whatsapp_api_campaign_id), a mesma lista que
#   Messages::EnvioAutomatico lê e que a guarda por AST mantém em dia;
# - pesquisa de satisfação que sai como mensagem (`input_csat`: no WhatsApp ela é outgoing, CsatSurveyService);
# - cópia encaminhada de outra conversa (`forwarded`, ConversaCanal::Encaminhamento): quem encaminhou estava na origem;
# - modelo reenviado no encaminhamento fora da janela (`reenvio_do_modelo`, Whatsapp::Templates::ReenvioDoModelo).
# Só estrutura (tipo de conteúdo e marcas gravadas pela plataforma); nada do texto.
module Messages::NaoEResposta
  CONTEUDOS = %w[input_csat].freeze
  MARCAS = %w[forwarded reenvio_do_modelo].freeze

  module_function

  def nao_e_resposta?(message)
    atributos = message.content_attributes.to_h.with_indifferent_access
    ::Autonomia::Agents::Operate::PessoaDaEquipe.envio_automatico?(message) ||
      CONTEUDOS.include?(message.content_type) ||
      MARCAS.any? { |marca| atributos[marca].present? }
  end
end
