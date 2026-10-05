require 'rake'
require 'rails_helper'

# A conta da régua da busca (#977), sem banco de artigos e sem Jev.
RSpec.describe CentralDeAjudaAvaliacaoDaBusca do
  let(:avaliacao) { described_class }
  let(:resultados) do
    [
      { q: 'zap', ok: ['07.08'], conjunto: 'ajuste', palavras: %w[07.08 07.01], melhor: { id: '07.08', certeza: 0.9 } },
      { q: 'banido', ok: ['18.02'], conjunto: 'ajuste', palavras: %w[07.01 18.02], melhor: { id: '07.05', certeza: 0.3 } },
      { q: 'travou', ok: ['18.01'], conjunto: 'ajuste', palavras: [], melhor: { id: 'nenhum', certeza: nil } },
      { q: 'pdf', ok: ['08.08'], conjunto: 'ajuste', palavras: %w[01.01 01.02 01.03], melhor: { id: '08.08', certeza: 0.2 } }
    ]
  end

  it 'drops cases whose expected articles the account cannot see and keeps only the visible ones' do
    casos = [{ 'q' => 'a', 'ok' => %w[07.08 99.99] }, { 'q' => 'b', 'ok' => ['99.99'] }]

    expect(avaliacao.casos_visiveis(casos, ['07.08'])).to eq([{ 'q' => 'a', 'ok' => ['07.08'] }])
  end

  it 'counts the keyword search alone when the Jev is off' do
    placar = avaliacao.placar(resultados, com_jev: false)

    expect(placar.slice(:total, :palavras_no_1o, :palavras_nos_3, :vazios))
      .to eq(total: 4, palavras_no_1o: 1, palavras_nos_3: 2, vazios: 1)
    expect(placar[:erros].size).to eq(2)
  end

  it 'puts the Jev choice on top of the keyword list, ignoring "nenhum", and averages only the wrong certainties' do
    placar = avaliacao.placar(resultados, com_jev: true)

    expect(placar.slice(:jev_no_1o, :combinado_nos_3, :certeza_media_dos_erros))
      .to eq(jev_no_1o: 2, combinado_nos_3: 3, certeza_media_dos_erros: 0.3)
    expect(placar[:erros]).to contain_exactly(start_with('banido => 07.05'), start_with('travou => nenhum'))
  end

  it 'reads the service answer by the Central id, and counts nil or a crash as a miss without stopping' do
    servico = Object.new
    def servico.melhor(termo)
      raise ArgumentError if termo == 'quebra'

      termo == 'zap' ? { artigo: { id: '07.08' }, certeza: 0.8 } : nil
    end

    expect(avaliacao.melhor_resposta(servico, 'zap')).to eq(id: '07.08', certeza: 0.8)
    expect(avaliacao.melhor_resposta(servico, 'nada')).to eq(id: 'nenhum', certeza: nil)
    expect(avaliacao.melhor_resposta(servico, 'quebra')).to eq(id: 'falhou (ArgumentError)', certeza: nil)
  end

  it 'prints one line per set followed by its errors' do
    linhas = avaliacao.relatorio(resultados + [resultados.first.merge(conjunto: 'validacao')], com_jev: true)

    expect(linhas.first).to start_with('ajuste: 4 casos | palavras: 1º 1/4 (25%)')
    expect(linhas).to include(start_with('validacao: 1 casos'))
  end
end
