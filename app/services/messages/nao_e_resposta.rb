# Mensagem que uma pessoa manda pela conversa sem estar respondendo nela (#2202): não diz que alguém leu a conversa,
# então não apaga a bolinha de não lida (ConversaCanal::VistaAoResponder, que já deixa de fora tudo que não é de
# pessoa: robô, eco do celular, pesquisa de satisfação, saída sem remetente). A lista é uma só, aqui:
# - envio automático em nome de alguém e campanha: as marcas de Autonomia::Agents::Operate::PessoaDaEquipe
#   (automação, follow-up, convite e aviso do Agendamento, campaign_id, whatsapp_api_campaign_id), a mesma lista que
#   Messages::EnvioAutomatico lê e que a guarda por AST mantém em dia;
# - cópia encaminhada de outra conversa (`forwarded`, ConversaCanal::Encaminhamento): quem encaminhou estava na origem;
# - modelo reenviado no encaminhamento fora da janela (`reenvio_do_modelo`, Whatsapp::Templates::ReenvioDoModelo).
# Só estrutura (marcas gravadas pela plataforma); nada do texto.
# A mesma lista está no backfill do passado, em docs/2202-lista-conversas/backfill-bolinha.sql: mudou aqui, mude lá.
module Messages::NaoEResposta
  MARCAS = %w[forwarded reenvio_do_modelo].freeze

  module_function

  def nao_e_resposta?(message)
    atributos = message.content_attributes.to_h.with_indifferent_access
    ::Autonomia::Agents::Operate::PessoaDaEquipe.envio_automatico?(message) ||
      MARCAS.any? { |marca| atributos[marca].present? }
  end
end
