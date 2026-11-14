# "Trazer" o lote de PDFs (E6.3, #2899): confere e põe a gravação na fila (Carteira::TrazerPdfsJob, só com o id da
# leitura). O segundo clique responde o mesmo, sem pôr outra gravação na fila; a gravação que parou (o processo morreu)
# volta para a fila quando alguém pede de novo depois de PARADA.
#
# - Ainda lendo: `leitura_nao_pronta`. Nenhum PDF pronto (todos pedem algo, ou ficaram de fora): `nada_para_trazer`.
# - Só entram os PDFs prontos (Carteira::Trazer::Pdfs::ItemDoConferir#pronto?); os que pedem algo não entram e não
#   seguram os outros. `totais.para_trazer` guarda quantos vão, para o andamento.
class Carteira::Trazer::Pdfs::Trazer
  PARADA = 10.minutes

  def initialize(leitura)
    @leitura = leitura
  end

  def call
    pedir = @leitura.with_lock { pedir? }
    Carteira::TrazerPdfsJob.perform_later(@leitura.id) if pedir
    @leitura
  end

  private

  def pedir?
    return parada? if @leitura.estado == 'trazendo'
    return false if %w[trazida desfazendo desfeita].include?(@leitura.estado)

    conferir = Carteira::Trazer::Pdfs::Conferir.new(@leitura)
    recusar('leitura_nao_pronta') unless conferir.call[:estado] == 'lida'
    prontos = conferir.vistas.count(&:pronto?)
    recusar('nada_para_trazer') if prontos.zero?

    @leitura.update!(estado: 'trazendo', totais: @leitura.totais.to_h.merge('para_trazer' => prontos))
  end

  def parada?
    return false if @leitura.updated_at > PARADA.ago

    @leitura.update!(updated_at: Time.current)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
