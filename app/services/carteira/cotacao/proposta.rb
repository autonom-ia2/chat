# O envio da proposta de renovação ao segurado (E8, #2901): o modelo da Finalidade `renovacao_proposta`, com o PDF da
# proposta guardado na nota privada (Carteira::Cotacao::Pronta) no topo, com o nome "Proposta de renovação.pdf"
# (Whatsapp::Templates::HeaderMedia.dispatch_file). Sai pela caixa escolhida, com as conferências do envio
# (Carteira::Cotacao::Envio: recusa relida do banco, caixa, modelo aprovado).
#
# Duas portas: sozinho (`quem_envia = sozinho`, logo que a proposta fica pronta; passo `proposta_enviada_sozinha`) e o
# clique em "Enviar" no card (`user`; passo `proposta_enviada` com quem clicou). Uma vez só por vigência, e nada sai em
# dobro: sob a trava do seguro só se confere o passo e se grava o do envio, ANTES de qualquer coisa sair, e a transação
# fecha ali; a mensagem à Meta sai depois, fora da trava. O segundo clique (ou a passada sozinha) encontra o passo e
# para. No clique, o que impede vira recusa para a tela (CustomExceptions::CarteiraRecusa): `cotacao_desligada`,
# `proposta_ja_enviada`, `sem_proposta` ou o motivo do envio que não saiu. Sozinho, nada é levantado.
# O envio que não saiu (antes da trava, nas conferências, ou depois, na mensagem) fica na história (`proposta_nao_saiu`,
# motivo `envio`) e avisa a equipe, nas duas portas. Esse passo vem depois do passo do envio, e por isso a proposta volta
# a poder ser enviada (`enviada?` olha o último dos dois).
class Carteira::Cotacao::Proposta
  FINALIDADE = 'renovacao_proposta'.freeze
  ENVIADA = 'proposta_enviada'.freeze
  SOZINHA = 'proposta_enviada_sozinha'.freeze
  NAO_SAIU = 'proposta_nao_saiu'.freeze
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
    conferir!
    mandar(reservar!)
  rescue Parou => e
    raise CustomExceptions::CarteiraRecusa, e.message if @user

    nil
  end

  # A proposta saiu nesta vigência, por uma das duas portas, e o que veio depois não foi um envio que não saiu.
  def self.enviada?(apolice)
    ultimo = apolice.eventos.where(tipo: [ENVIADA, SOZINHA, NAO_SAIU])
                    .where("valores->>'vigencia' = ?", apolice.fim_vigencia.iso8601).order(:quando, :id).last
    [ENVIADA, SOZINHA].include?(ultimo&.tipo)
  end

  private

  def envio
    @envio ||= Carteira::Cotacao::Envio.new(@apolice, @config, user: @user)
  end

  # As conferências do envio antes da trava (recusa, caixa, modelo): o que já se sabe que não sai não reserva nada.
  def conferir!
    envio.conferir!(FINALIDADE)
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu(e.message)
  end

  # Sob a trava, só o passo: relido, e o do envio gravado com quem clicou antes de qualquer coisa sair. -> o PDF.
  def reservar!
    @apolice.with_lock(requires_new: true) do
      parar('proposta_ja_enviada') if self.class.enviada?(@apolice)
      blob = arquivo || parar('sem_proposta')
      Carteira::Cotacao.registrar(@apolice, @user ? ENVIADA : SOZINHA, user: @user)
      blob
    end
  end

  # Fora da trava: a mensagem com o PDF no topo. Falhou, o passo `proposta_nao_saiu` vem depois do envio e deixa tentar
  # de novo.
  def mandar(blob)
    topo = ->(caixa) { Whatsapp::Templates::HeaderMedia.dispatch_file(blob, caixa).merge('media_type' => 'document') }
    envio.modelo(FINALIDADE, Carteira::Cotacao::ETAPA_PROPOSTA, topo: topo)
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu(e.message)
  rescue StandardError => e
    Rails.logger.warn("[carteira][cotacao] proposta nao saiu apolice=#{@apolice.id} #{e.class}")
    nao_saiu('erro')
  end

  # O PDF da proposta pronta desta vigência: o anexo da nota privada que a guardou.
  def arquivo
    pronta = Carteira::Cotacao.passo(@apolice, Carteira::Cotacao::Pronta::PRONTA)
    nota = pronta && Message.find_by(id: pronta.valores.to_h['nota'], account_id: @apolice.account_id)
    nota&.attachments&.first&.file&.blob
  end

  def nao_saiu(motivo)
    Carteira::Cotacao.registrar(@apolice, NAO_SAIU, motivo: 'envio', detalhe: motivo)
    Carteira::Cotacao::Aviso.new(@apolice, 'proposta_nao_saiu', detalhe: motivo).call
    parar(motivo)
  end

  def parar(codigo)
    raise Parou, codigo
  end
end
