# Lê os eventos da Prospecção (#732 item 13, ENRIQ-60) que o código escreveu no log do Rails durante o bloco. Devolve
# o texto inteiro do log, para o teste provar que nada pessoal vazou, e os eventos já decodificados do JSON.
module ProspectingEventLogHelpers
  CapturedLog = Struct.new(:text, :events, keyword_init: true)

  def capture_prospecting_events
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    yield
    prefix = Autonomia::Prospecting::EventLog::PREFIX
    events = output.string.lines.filter_map do |line|
      JSON.parse(line.delete_prefix(prefix).strip) if line.start_with?(prefix)
    end
    CapturedLog.new(text: output.string, events: events)
  end
end
