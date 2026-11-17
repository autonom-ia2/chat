# O envio da proposta de renovação ao segurado (E8, #2901): o modelo da Finalidade `renovacao_proposta`, com o PDF da
# proposta guardado na nota privada (Carteira::Cotacao::Pronta) no topo, com o nome "Proposta de renovação.pdf"
# (Whatsapp::Templates::HeaderMedia.dispatch_file). Sai pela caixa escolhida, com as conferências do envio
# (Carteira::Cotacao::Envio: recusa relida do banco, caixa, modelo aprovado).
#
# Duas portas: sozinho (`quem_envia = sozinho`, logo que a proposta fica pronta; passo `proposta_enviada_sozinha`) e o
# clique em "Enviar" no card (`user`; passo `proposta_enviada` com quem clicou). Uma vez só por vigência: o seguro fica
# travado e o passo é relido sob a trava. No clique, o que impede vira recusa para a tela (CustomExceptions::CarteiraRecusa):
# `cotacao_desligada`, `proposta_ja_enviada`, `sem_proposta` ou o motivo do envio que não saiu. Sozinho, nada é levantado.
# O envio que não saiu fica na história (`proposta_nao_saiu`, motivo `envio`) e avisa a equipe, nas duas portas.
class Carteira::Cotacao::Proposta
  FINALIDADE = 'renovacao_proposta'.freeze
  ENVIADA = 'proposta_enviada'.freeze
  SOZINHA = 'proposta_enviada_sozinha'.freeze
  # O que impede o envio, antes de qualquer coisa sair.
  class Parou < StandardError; end

  def initialize(apolice, config, user: nil)
    @apolice = apolice
    @config = config
    @user = user
  end

  # -> a mensagem enviada, ou nil (sozinho, quando não saiu).
  def enviar
    parar('cotacao_desligada') unless Carteira::Cotacao.aberta?(@apolice.account, @config)
    falha = nil
    mensagem = @apolice.with_lock(requires_new: true) do
      mandar
    rescue Carteira::Cotacao::Envio::NaoSaiu => e
      falha = e.message
      nil
    end
    falha ? nao_saiu(falha) : mensagem
  rescue Parou => e
    raise CustomExceptions::CarteiraRecusa, e.message if @user

    nil
  end

  # A proposta já saiu nesta vigência, por uma das duas portas.
  def self.enviada?(apolice)
    [ENVIADA, SOZINHA].any? { |tipo| Carteira::Cotacao.passo(apolice, tipo) }
  end

  private

  def mandar
    parar('proposta_ja_enviada') if self.class.enviada?(@apolice)
    blob = arquivo || parar('sem_proposta')
    topo = ->(caixa) { Whatsapp::Templates::HeaderMedia.dispatch_file(blob, caixa).merge('media_type' => 'document') }
    mensagem = Carteira::Cotacao::Envio.new(@apolice, @config, user: @user)
                                       .modelo(FINALIDADE, Carteira::Cotacao::ETAPA_PROPOSTA, topo: topo)
    Carteira::Cotacao.registrar(@apolice, @user ? ENVIADA : SOZINHA, { mensagem: mensagem.id }, user: @user)
    mensagem
  end

  # O PDF da proposta pronta desta vigência: o anexo da nota privada que a guardou.
  def arquivo
    pronta = Carteira::Cotacao.passo(@apolice, Carteira::Cotacao::Pronta::PRONTA)
    nota = pronta && Message.find_by(id: pronta.valores.to_h['nota'], account_id: @apolice.account_id)
    nota&.attachments&.first&.file&.blob
  end

  def nao_saiu(motivo)
    Carteira::Cotacao.registrar(@apolice, Carteira::Cotacao::Cotar::NAO_SAIU, motivo: 'envio', detalhe: motivo)
    Carteira::Cotacao::Aviso.new(@apolice, 'proposta_nao_saiu', detalhe: motivo).call
    parar(motivo)
  end

  def parar(codigo)
    raise Parou, codigo
  end
end
