# "Trazer" a primeira busca no conector (E7, #2900), do Conferir: confere e põe a gravação na fila
# (Carteira::Conector::GravarJob, só com o id da leitura). O segundo clique responde o mesmo, sem pôr outra gravação na
# fila; a gravação que parou (o processo morreu) volta para a fila quando alguém pede de novo depois de PARADA.
#
# - Ainda buscando (ou parada): `leitura_nao_pronta`. Nenhum registro pronto: `nada_para_trazer`. Quantos estão prontos
#   vem do que o job da busca já calculou (Carteira::Conector::Conferir#prontos lê `totais`): a requisição não procura a
#   pessoa de registro nenhum, e a trava fica só o tempo de mudar o estado. A gravação é o job (Carteira::Conector::GravarJob).
# - `totais.para_trazer` guarda quantos registros passam pela gravação (os prontos entram; os outros contam como "não deu
#   para trazer"), para o andamento.
class Carteira::Conector::Trazer
  PARADA = Carteira::Trazer::Pdfs::Trazer::PARADA

  def initialize(leitura)
    @leitura = leitura
  end

  def call
    pedir = @leitura.with_lock { pedir? }
    Carteira::Conector::GravarJob.perform_later(@leitura.id) if pedir
    @leitura
  end

  private

  def pedir?
    return parada? if @leitura.estado == 'trazendo'
    return false if %w[trazida desfazendo desfeita].include?(@leitura.estado)

    recusar('leitura_nao_pronta') unless @leitura.estado == 'lida'
    recusar('nada_para_trazer') if Carteira::Conector::Conferir.new(@leitura).prontos.zero?

    lidos = @leitura.itens.where(estado: Carteira::Conector::Ler::LIDO).count
    @leitura.update!(estado: 'trazendo', totais: @leitura.totais.to_h.merge('para_trazer' => lidos))
  end

  def parada?
    return false if @leitura.updated_at > PARADA.ago

    @leitura.update!(updated_at: Time.current)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
