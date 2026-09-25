require 'rails_helper'

# O TEXTO QUE A FERRAMENTA DE COTAÇÃO DEVOLVE AO MODELO NÃO TRAZ TRAVESSÃO NEM CRASE (chat#641, 25/09/2026).
#
# O modelo copia a pontuação que lê: o travessão é o tique que denuncia texto de IA, e a crase sai literal no WhatsApp.
# A conferência (`conferencia_para_o_modelo`) montava "campo — motivo", e o especialista repassava o travessão. Aqui
# ficam os textos da cotação que voltam ao modelo como resultado de ferramenta, conferidos por método de string.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  describe 'o texto da cotação que volta ao modelo' do
    let(:proibidos) { ['—', '–', '`'] }
    let(:cotacao) { described_class }

    def sem_proibidos?(texto)
      proibidos.none? { |sinal| texto.include?(sinal) }
    end

    it 'a conferência separa campo e motivo sem travessão' do
      texto = cotacao.allocate.conferencia_para_o_modelo(
        [{ 'campo' => 'coverage.assistance24h', 'motivo' => '2000 não existe nesta cobertura.' },
         { 'campo' => 'configuracoes.isDanosDespesasFixas', 'motivo' => 'acima do teto.' }]
      )

      expect(texto).to include('coverage.assistance24h: 2000 não existe nesta cobertura.')
      expect(sem_proibidos?(texto)).to be(true), texto
    end

    it 'as recusas, os fatos dos eventos e a descrição da ferramenta não trazem travessão nem crase' do
      textos = {
        'PEDIDO_DE_JSON' => cotacao::PEDIDO_DE_JSON, 'RAMO_DESCONHECIDO' => cotacao::RAMO_DESCONHECIDO,
        'SEM_ITEM' => cotacao::SEM_ITEM, 'SEM_VEICULO' => cotacao::SEM_VEICULO, 'SEM_FORMULARIO' => cotacao::SEM_FORMULARIO,
        'CONEXAO_FORA' => cotacao::CONEXAO_FORA, 'DESCRICAO' => cotacao::DESCRICAO
      }.merge(cotacao::FATOS.transform_keys { |tipo| "FATOS[#{tipo}]" })
      sujos = textos.reject { |_, texto| sem_proibidos?(texto) }.keys

      expect(sujos).to be_empty, "texto ao modelo com travessão ou crase: #{sujos.join(', ')}"
    end

    it 'o pedido repetido não traz travessão nem crase' do
      run = Autonomia::Agents::ToolRun.new(id: 1, slug: 'cotar_seguro', status: 'running', handle: {}, created_at: 2.minutes.ago)
      texto = Autonomia::Agents::Tools::PedidoRepetido.new(run).to_s

      expect(texto).to include('dado diferente abre consulta nova')
      expect(sem_proibidos?(texto)).to be(true), texto
    end
  end
end
