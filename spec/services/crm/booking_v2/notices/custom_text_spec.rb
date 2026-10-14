require 'rails_helper'

# Texto próprio de um aviso (#1354): a conferência (ao salvar, ao receber da IA e no envio) e o preenchimento.
RSpec.describe Crm::BookingV2::Notices::CustomText do
  let(:good) { 'Oi, {{cliente.primeiro_nome}}! Seu horário na {{minha_empresa.nome}} é {{horario.data_hora}}. Mude em {{horario.link_gestao}}' }
  let(:values) do
    { 'cliente.primeiro_nome' => 'Ana', 'horario.data_hora' => '20/10 às 10:00', 'horario.link_gestao' => 'https://x.test/b/AB',
      'minha_empresa.nome' => 'Studio Bela' }
  end
  let(:resolver) { instance_double(TemplateFields::Resolver) }

  before { allow(resolver).to receive(:value) { |key| values[key] } }

  describe '.problem' do
    it 'aceita só as chaves do aviso, com link e dia/hora, até o tamanho máximo' do
      expect(described_class.problem(good)).to be_nil
    end

    # 10. #1517: o link deixou de ser obrigatório (vai no botão ou na linha fixa); o dia e a hora continuam.
    it 'aceita texto sem o link e continua recusando texto sem o dia e a hora' do
      expect(described_class.problem('Seu horário é {{horario.data_hora}}.')).to be_nil
      expect(described_class.problem('Mude em {{horario.link_gestao}}.')).to eq(:missing_when)
      expect(described_class::REQUIRED_KEYS).to eq(['horario.data_hora'])
    end

    it 'diz o motivo de cada recusa' do
      expect(described_class.problem('  ')).to eq(:blank)
      expect(described_class.problem("{{horario.data_hora}} {{horario.link_gestao}} #{'a' * 500}")).to eq(:too_long)
      expect(described_class.problem('Oi {{horario.data_hora}} {{horario.link_gestao')).to eq(:malformed)
      expect(described_class.problem('Oi {{cliente.cpf}} {{horario.data_hora}} {{horario.link_gestao}}')).to eq(:unknown_field)
      expect(described_class.problem('Oi {{1}} {{horario.data_hora}} {{horario.link_gestao}}')).to eq(:unknown_field)
      expect(described_class.problem('Mude em {{horario.link_gestao}}.')).to eq(:missing_when)
    end

    it 'recusa colchete que sobrou (rótulo de campo da tela que não virou chave)' do
      expect(described_class.problem('Oi [Primeiro nome] {{horario.data_hora}} {{horario.link_gestao}}')).to eq(:bracket)
    end

    it 'recusa a linha de parar, que é do sistema (em qualquer idioma)' do
      expect(described_class.problem("#{good}\nPara parar estes avisos: x")).to eq(:stop_line)
      expect(described_class.problem("#{good}\nTo stop these messages: x")).to eq(:stop_line)
    end
  end

  describe '.fill' do
    it 'troca as chaves pelos valores' do
      expect(described_class.fill(good, resolver)).to eq('Oi, Ana! Seu horário na Studio Bela é 20/10 às 10:00. Mude em https://x.test/b/AB')
    end

    it 'sem primeiro nome, tira o campo e a vírgula ou o espaço que sobraria' do
      values['cliente.primeiro_nome'] = nil

      expect(described_class.fill(good, resolver)).to start_with('Oi! Seu horário')
      expect(described_class.fill('Olá {{cliente.primeiro_nome}}, seu horário é {{horario.data_hora}}: {{horario.link_gestao}}', resolver))
        .to eq('Olá, seu horário é 20/10 às 10:00: https://x.test/b/AB')
      expect(described_class.fill('{{cliente.primeiro_nome}}, seu horário é {{horario.data_hora}}: {{horario.link_gestao}}', resolver))
        .to eq('seu horário é 20/10 às 10:00: https://x.test/b/AB')
    end

    it 'devolve nil (o envio cai no padrão) com texto inválido ou sem link/dia para preencher' do
      expect(described_class.fill('Sem dia {{horario.link_gestao}}', resolver)).to be_nil
      expect(described_class.fill('Sem link {{horario.data_hora}}', resolver)).to eq('Sem link 20/10 às 10:00')

      values['horario.link_gestao'] = nil
      expect(described_class.fill(good, resolver)).to be_nil
    end
  end

  it 'monta o texto padrão de cada aviso com as chaves, como ponto de partida' do
    expect(described_class.default_text('booked', locale: 'pt_BR')).to eq(
      'Oi, {{cliente.primeiro_nome}}! Seu horário está marcado para {{horario.data_hora}}. Para confirmar, mudar ou cancelar: {{horario.link_gestao}}'
    )
    Crm::MeetingNotice::KINDS.each { |kind| expect(described_class.problem(described_class.default_text(kind, locale: 'en'))).to be_nil }
  end
end
