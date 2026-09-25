require 'rails_helper'

# NENHUM TEXTO QUE CHEGA AO MODELO DIZ ONDE O ARQUIVO ESTÁ (chat#641, 25/09/2026).
#
# Na conversa real, depois do comparativo, a Lia escreveu que ele estava "no PDF acima". No banco o anexo foi gravado
# antes do texto, mas no WhatsApp o upload do PDF atrasa a entrega e ele chegou depois: a fala mentia. A frase veio do
# fato do evento (`Eventos::FATOS`, "logo acima") e do título da §14 do principal ("com o comparativo acima"). A ordem
# entre arquivo e mensagem não é garantida no canal, então nenhum texto de instrução ou de sistema pode falar em
# posição do arquivo, em nenhum ramo.
#
# A guarda lê cada frase por método de string, sem regex: uma frase que fala de arquivo e de posição reprova.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  describe 'a posição do arquivo nos textos do Agente de Cotação' do
    let(:instrucoes) { Rails.root.join('app/services/autonomia/insurance/quote_agent/instrucoes') }
    let(:posicoes) { %w[acima abaixo] }
    let(:arquivo) { %w[pdf anexo arquivo comparativo proposta] }

    # -> as frases do texto que falam de arquivo e de posição ao mesmo tempo.
    def frases_com_posicao(texto)
      texto.tr("\n", ' ').split('. ').select do |frase|
        minuscula = frase.downcase
        posicoes.any? { |palavra| minuscula.include?(palavra) } && arquivo.any? { |palavra| minuscula.include?(palavra) }
      end
    end

    def run_de_cotacao
      Autonomia::Agents::ToolRun.new(id: 1, slug: 'cotar_seguro', handle: {})
    end

    it 'a guarda reconhece a frase da conversa real e a do fato antigo' do
      expect(frases_com_posicao('O comparativo, considerando R$ 220 mil, está no PDF acima.')).to be_present
      expect(frases_com_posicao('O comparativo em PDF acabou de ser enviado nesta conversa, logo acima.')).to be_present
      expect(frases_com_posicao('O bloco acima vale para você.')).to be_empty
    end

    it 'os manuais de todos os ramos, o principal e o bloco comum não põem o arquivo em posição' do
      manuais = Dir[instrucoes.join('*.md')]
      expect(manuais.map { |caminho| File.basename(caminho) })
        .to include('principal.md', 'comum_especialista.md', 'especialista_auto.md', 'especialista_residencial.md',
                    'especialista_empresarial.md')

      achados = manuais.flat_map do |caminho|
        frases_com_posicao(File.read(caminho)).map { |frase| "#{File.basename(caminho)}: #{frase.strip}" }
      end
      expect(achados).to be_empty, "texto que diz onde o arquivo está:\n#{achados.join("\n")}"
    end

    it 'os fatos dos eventos e a descrição de cada evento não põem o arquivo em posição' do
      eventos = Autonomia::Agents::Tools::Native::InsuranceQuote::Eventos
      textos = eventos::FATOS.values + Autonomia::Agents::Tools::Evento::DESCRICOES.values
      achados = textos.flat_map { |texto| frases_com_posicao(texto) }
      expect(achados).to be_empty, "fato de evento que diz onde o arquivo está:\n#{achados.join("\n")}"
    end

    it 'o aviso do sistema que a Lia lê quando o comparativo sai não põe o arquivo em posição, e diz que a ordem varia' do
      %w[concluida encerrada_por_prazo].each do |tipo|
        nota = Autonomia::Agents::Tools::Evento.new(run: run_de_cotacao, tipo: tipo).nota_do_sistema
        expect(nota).to include('comparativo em PDF')
        expect(nota).to include(Autonomia::Agents::Tools::Native::InsuranceQuote::Eventos::ORDEM_DO_ARQUIVO)
        expect(frases_com_posicao(nota)).to be_empty
      end
    end

    it 'o texto da proposta enviada não põe o arquivo em posição, e diz que a ordem varia' do
      enviada = format(Autonomia::Agents::Tools::Native::InsuranceQuoteProposal::ENVIADA, nome: 'Porto')
      expect(enviada).to include(Autonomia::Agents::Tools::Native::InsuranceQuote::Eventos::ORDEM_DO_ARQUIVO)
      expect(frases_com_posicao(enviada)).to be_empty
    end
  end
end
