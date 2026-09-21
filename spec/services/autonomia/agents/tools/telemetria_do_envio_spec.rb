require 'rails_helper'

# A REGRA QUE ESTE MÓDULO EXISTE PARA CUMPRIR: rótulo nosso no log, mensagem nunca.
#
# Sem estes exemplos a regra é só comentário. Provado por mutação na revisão da PR #561: trocar
# `erro.etiqueta` por `erro.message` no rótulo passava em todos os testes da suíte, e a mensagem
# de um erro de `validation` é `business_message(payload)` — texto que vem do adapter e pode
# carregar o que o portal disse, inclusive documento de cliente.
RSpec.describe Autonomia::Agents::Tools::TelemetriaDoEnvio do
  let(:run) { instance_double(Autonomia::Agents::ToolRun, id: 42, slug: 'cotar_seguro') }

  def erro_do_connector(kind, mensagem, causa)
    Autonomia::Insurance::Connector::Error.new(kind, mensagem, {}, causa: causa)
  end

  describe '.rotulo' do
    it 'usa categoria e porta, e descarta a mensagem que veio do portal' do
      # Arrange — é assim que a mensagem chega quando o adapter recusa a entrada
      erro = erro_do_connector(:validation, 'CPF 123.456.789-00 recusado pelo portal', :status_do_handler)

      # Act / Assert
      expect(described_class.rotulo(erro)).to eq('validation/status_do_handler')
    end

    it 'exceção comum entra pela classe, nunca pela mensagem' do
      # Arrange — a mensagem de um erro de rede pode carregar a requisição assinada
      erro = StandardError.new('POST https://lambda.amazonaws.com/... X-Amz-Credential=AKIA...')

      # Act / Assert
      expect(described_class.rotulo(erro)).to eq('StandardError')
    end
  end

  describe '.falha_do_start' do
    it 'a linha do log leva o motivo dado, e nada além dele' do
      # Arrange
      allow(Rails.logger).to receive(:warn)

      # Act
      described_class.falha_do_start(run: run, intencao: 1, o_que: 'start falhou',
                                     motivo: 'unavailable/invoke_recusado')

      # Assert
      expect(Rails.logger).to have_received(:warn)
        .with('[autonomia][tool][async] start falhou run=42 slug=cotar_seguro ' \
              'intencao=1 motivo=unavailable/invoke_recusado')
    end
  end
end
