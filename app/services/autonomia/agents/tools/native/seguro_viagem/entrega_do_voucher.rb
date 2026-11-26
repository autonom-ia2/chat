# O VOUCHER EM PDF COMO CARTÃO DO TURNO (#3246), no mesmo caminho do comparativo (`EntregaDoComparativo`):
# `situacao_do_pagamento` (pagamento feito, voucher ainda não enviado nesta cotação) e `segunda_via_do_voucher` só marcam
# o cartão (`cartao`); o `Operate::CartoesDoTurno` o posta depois da resposta do turno, com o token e os descartes de
# sempre. Com responsável na conversa vira nota privada, como o comparativo.
#
# EM DUAS METADES, para a rede ficar fora do lock da conversa (`CartoesDoTurno#voucher!`):
#   - `baixar`, sem lock: pede à Universal a URL do PDF (`url_do_voucher`, pelo carrinho da proposta guardada) e baixa o
#     PDF com `Tools::EntregaDeArquivo` (só https, sem redirecionamento, assinatura `%PDF-`, até 10 MB), que já o grava
#     no armazenamento. A URL leva o token do carrinho: nunca vai a log.
#   - `criar`, sob o lock: anexa o PDF numa mensagem sem texto e grava `voucher_enviado_em` na proposta, sob o lock da
#     cotação (a ordem dos locks é conversa, depois cotação; a proposta e a situação do pagamento só travam a cotação).
#
# A FALHA NÃO FALA COM O CLIENTE. A Universal fora, o acesso recusado, o voucher não encontrado, a URL que responde outra
# coisa que não PDF (o JSON de "pagamento ainda não realizado") ou o armazenamento fora: uma nota PRIVADA para a equipe
# (uma por cartão) e um log só com ids e o código da falha. O PDF leva CPF, endereço e nascimento: só vai à conversa do
# próprio cliente, nunca a log.
class Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Arquivo = Autonomia::Agents::Tools::EntregaDeArquivo
  TIPO_DO_CARTAO = 'voucher_viagem'.freeze
  CHAVE = 'autonomia_voucher_viagem'.freeze
  NOME_DO_ARQUIVO = 'voucher-seguro-viagem.pdf'.freeze
  # O motivo do cartão que não saiu, para o `EnviarCartoesJob` (`cartao_nao_enviado`).
  NAO_SAIU = 'voucher_nao_saiu'.freeze
  NOTA = 'autonomia.contratados.universal.notas.voucher_nao_saiu'.freeze
  FALHAS = [Autonomia::Seguradoras::Universal::Cliente::Erro, Arquivo::Indisponivel].freeze

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

  # `atributos`: o que o cartão grava na mensagem (o agente e o token do turno).
  def initialize(conversation:, cotacao:, sender_id:, atributos:)
    @conversation = conversation
    @cotacao = cotacao
    @sender_id = sender_id
    @atributos = atributos
  end

  # FORA do lock da conversa. -> o `ActiveStorage::Blob` do PDF, já gravado; nil quando o voucher não saiu (a nota da
  # equipe já foi postada).
  def baixar
    acesso = @cotacao.agent.acesso_da_seguradora
    return nao_saiu('sem_acesso') unless acesso&.ok?

    resposta = SeguroViagem::Pagamento.cliente(@cotacao.agent).url_do_voucher(SeguroViagem::Pagamento.carrinho(@cotacao))
    arquivo = Arquivo.new(url: resposta.is_a?(Hash) ? resposta['url'] : nil, nome: NOME_DO_ARQUIVO)
    return nao_saiu("forma_#{arquivo.defeito}") unless arquivo.valida?

    arquivo.gravar
  rescue *FALHAS => e
    nao_saiu(e.is_a?(Arquivo::Indisponivel) ? e.motivo : e.codigo)
  end

  # SOB o lock da conversa (quem chama já conferiu as guardas). -> a mensagem com o PDF.
  def criar(blob)
    mensagem = Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: nil, attachments: [blob.signed_id], message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @sender_id, private: @conversation.assignee_id.present?,
        content_attributes: @atributos.merge(CHAVE => @cotacao.id)
      )
    ).perform
    marcar_enviado
    mensagem
  end

  private

  def marcar_enviado
    @cotacao.with_lock do
      @cotacao.update!(proposta: @cotacao.proposta.to_h.merge('voucher_enviado_em' => Time.current.iso8601))
    end
  end

  # -> nil. `falha` é um código curto e fechado (o do cliente HTTP ou o da entrega de arquivo), nunca a URL nem o corpo.
  def nao_saiu(falha)
    Rails.logger.warn("[autonomia][seguro_viagem] voucher_nao_saiu conv=#{@conversation.id} cotacao=#{@cotacao.id} falha=#{falha}")
    Autonomia::Insurance::NotaNaHora.postar(@conversation, I18n.t(NOTA),
                                            chave: "universal:voucher:#{@atributos['autonomia_cartao_token']}")
    nil
  end
end
