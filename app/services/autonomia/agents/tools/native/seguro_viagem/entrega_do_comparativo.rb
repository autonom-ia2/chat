# O COMPARATIVO EM PDF COMO CARTÃO DO TURNO (#3211, #3223): `cotar_seguro_viagem` não posta nada; marca o cartão
# (`cartao`) no contexto do turno, e o `Operate::CartoesDoTurno` o posta depois da resposta, só quando ela saiu, com o
# token e o descarte dos outros cartões (turno superado, silêncio, pessoa respondeu). Antes, o PDF saía de dentro da
# ferramenta, e o turno que era descartado depois deixava o PDF na conversa sem a resposta (o primeiro teste real).
#
# NÃO DEPENDE DA FLAG DOS CARTÕES (`agentes_enviar_local_e_contato`): o cartão não tem formato (`rich_message` nil); o
# PDF nasce na hora de postar, da cotação guardada (`cotacao_do`), e sai como anexo sem legenda (quem fala junto é a
# resposta do turno). Com responsável na conversa vira nota privada, como sempre. O marcador `CHAVE` (o id da cotação)
# continua na mensagem.
#
# Erro ao gerar ou postar SOBE para o `EnviarCartoesJob`, que registra `cartao_nao_enviado` motivo=erro_ao_postar (log
# com ids e a classe, tracker) e não relança: a resposta já saiu. O blob da falha ao criar a mensagem é apagado.
class Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  TIPO_DO_CARTAO = 'comparativo_viagem'.freeze
  CHAVE = 'autonomia_comparativo_viagem'.freeze
  NOME_DO_ARQUIVO = 'comparativo-seguro-viagem.pdf'.freeze

  # O cartão que a ferramenta marca no turno (`Delivery#marcar_cartao`): o tipo e o id da cotação, sem formato.
  def self.cartao(cotacao)
    { 'tipo' => TIPO_DO_CARTAO, 'chave' => cotacao.id.to_s, 'rich_message' => nil }
  end

  def self.cartao?(cartao)
    cartao.to_h['tipo'] == TIPO_DO_CARTAO
  end

  # A cotação do cartão, só desta conversa; nil quando ela não existe mais.
  def self.cotacao_do(cartao, conversation)
    Autonomia::Agents::CotacaoDeViagem.find_by(id: cartao['chave'].to_i, conversation_id: conversation.id)
  end

  # `atributos`: o que o cartão grava na mensagem (o agente e o token do turno). Quem chama já tem o lock da conversa e
  # já conferiu que o cartão não saiu (`CartoesDoTurno#postar!`).
  def initialize(conversation:, cotacao:, sender_id:, atributos:)
    @conversation = conversation
    @cotacao = cotacao
    @sender_id = sender_id
    @atributos = atributos
  end

  def postar!
    blob = gravar_blob
    begin
      criar(blob)
    rescue StandardError
      blob.purge
      raise
    end
  end

  def criar(blob)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: nil, attachments: [blob.signed_id], message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @sender_id, private: @conversation.assignee_id.present?,
        content_attributes: @atributos.merge(CHAVE => @cotacao.id)
      )
    ).perform
  end

  private

  def gravar_blob
    nome = @cotacao.agent.marca_do_contratado.to_h['nome_corretora']
    pdf = SeguroViagem::ComparativoPdf.new(cotacao: @cotacao, nome_corretora: nome).render
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(pdf), filename: NOME_DO_ARQUIVO, content_type: 'application/pdf')
  end
end
