# "Trazer minha lista" com seguros (E4, #2897): a parte dos seguros no "Desfazer" de uma lista trazida
# (Relacionamentos::Trazer::Desfazer chama aqui ANTES de mexer nas pessoas). Quem diz o que sai, o que volta e o que
# fica é Carteira::Trazer::SegurosDaLista, a mesma leitura da prévia.
#
# - O seguro que a lista só completou volta ao que era: os campos que ela mudou recebem o valor de antes e os passos que
#   ela deixou na história dele saem.
# - O seguro que a lista criou e em que ninguém mexeu sai da carteira, com a história dele.
#
# Cada seguro é conferido de novo com ele travado, logo antes de mudar: quem ganhou correção, PDF ou card de renovação
# enquanto o bloco andava fica. O seguro em que a escrita dá errado (o fim de antes que hoje é de outro termo, um erro
# do banco) fica também, e os outros seguem: no registro vai só o id e a classe do erro, nunca a mensagem.
#
# Rodar de novo não repete nada: o que saiu não existe mais, e o que voltou já não tem passo desta lista. O bloco
# recebido é chamado a cada passo, para o Desfazer mostrar que está vivo.
class Carteira::Trazer::DesfazerSeguros
  BLOCO = Carteira::Trazer::SegurosDaLista::BLOCO

  def initialize(importacao)
    @lista = Carteira::Trazer::SegurosDaLista.new(importacao)
  end

  def call(&)
    return unless @lista.tem?

    devolver(&)
    tirar(&)
  end

  private

  def devolver
    @lista.que_voltam do |bloco|
      bloco.map(&:first).each { |apolice| com_cuidado(apolice) { voltar(apolice) } }
      yield if block_given?
    end
  end

  def tirar
    @lista.saem.in_batches(of: BLOCO) do |apolices|
      apolices.each { |apolice| com_cuidado(apolice) { apolice.destroy! if @lista.sai?(apolice) } }
      yield if block_given?
    end
  end

  def voltar(apolice)
    colunas = @lista.volta(apolice)
    return if colunas.nil?

    apolice.update!(colunas)
    @lista.passos_da_lista_em(apolice).delete_all
  end

  # Com a apólice travada e relida, numa transação só dela: o que der errado desfaz só o que era deste seguro.
  def com_cuidado(apolice, &)
    apolice.with_lock(requires_new: true, &)
  rescue ActiveRecord::RecordNotFound
    nil
  rescue StandardError => e
    Rails.logger.warn("[carteira][trazer][desfazer] apolice=#{apolice.id} kept: #{e.class.name}")
  end
end
