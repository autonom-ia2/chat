require 'rails_helper'

# O AGENTE DE COTAÇÃO NASCE PRONTO — ou não nasce.
#
# O que estes exemplos travam é a promessa da tela: quem clica em "Criar Agente de Cotação" recebe um
# agente que sabe cotar, com a instrução que a Autonom.ia mantém, e sem ter escrito uma linha. Um
# agente que nasce sem a ferramenta, ou sem o especialista, é pior que nenhum — ele responde sobre
# seguro e não cota.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) { create(:account) }

  def construir(**extra)
    described_class.new(
      account: account, nome_agente: 'Mia', nome_corretora: 'Corretora Exemplo', **extra
    ).call
  end

  describe 'o agente principal' do
    it 'nasce do tipo proprio, e nao como custom' do
      # Arrange / Act
      agente = construir

      # Assert — o tipo é o que separa este agente do construtor conversacional.
      expect(agente.agent_type).to eq('insurance_quote')
      expect(agente).to be_persisted
      expect(agente.enabled).to be(true)
    end

    it 'ja vem com as ferramentas que valem para toda conversa' do
      slugs = construir.native_tool_slugs

      expect(slugs).to include('consultar_produtos_disponiveis')
      expect(slugs).to include('consultar_condicoes_gerais')
    end

    # A ferramenta de cotação é reservada pelo especialista, e o Answerer a REMOVE da visão do
    # principal. Se ela também estivesse ligada nele, o principal cotaria por fora do especialista —
    # sem a jornada do ramo, sem a ordem de coleta, sem o aviso de bônus.
    it 'nao cota por conta propria' do
      expect(construir.native_tool_slugs).not_to include('cotar_seguro')
    end

    it 'carrega a instrucao da Autonom.ia, e nao um texto vazio' do
      instrucao = construir.instruction

      expect(instrucao.length).to be > 5_000
      expect(instrucao).to include('Você não cota')
      expect(instrucao).to include('consultar_condicoes_gerais')
    end
  end

  describe 'o especialista de auto' do
    it 'nasce junto, ligado e com a ferramenta de cotacao' do
      # Act
      agente = construir

      # Assert
      especialista = agente.specialists.find_by(slug: 'cotacao_auto')
      expect(especialista).to be_present
      expect(especialista.enabled).to be(true)
      expect(especialista.tool_slugs).to eq(['cotar_seguro'])
    end

    it 'carrega a jornada do ramo' do
      especialista = construir.specialists.find_by(slug: 'cotacao_auto')

      expect(especialista.instruction).to include('placa')
      expect(especialista.instruction).to include('Prata')
      # A armadilha que custou cotação para descobrir precisa sobreviver à criação.
      expect(especialista.instruction).to include('FLEX')
    end

    it 'aparece para o principal como uma funcao propria' do
      especialista = construir.specialists.find_by(slug: 'cotacao_auto')

      expect(especialista.function_name).to eq('consultar_cotacao_auto')
    end

    # A corretora acrescenta no campo dela, que entra DEPOIS — complementa, nunca sobrescreve.
    it 'deixa o campo da corretora vazio, para ela preencher' do
      especialista = construir.specialists.find_by(slug: 'cotacao_auto')

      expect(especialista.custom_instruction).to be_blank
      expect(especialista.effective_instruction).to eq(especialista.instruction)
    end
  end

  describe 'o que a corretora escolhe' do
    it 'escreve o nome do agente e da corretora na instrucao' do
      agente = described_class.new(
        account: account, nome_agente: 'Clara', nome_corretora: 'Seguros do Vale'
      ).call

      expect(agente.instruction).to include('Clara')
      expect(agente.instruction).to include('Seguros do Vale')
      # Nenhuma variável pode sobrar sem substituir: o modelo leria "$nomeAgente" como texto.
      expect(agente.instruction).not_to include('$nome')
    end

    it 'escreve o horario informado' do
      agente = construir(horario: 'todo dia, das 08h às 20h')

      expect(agente.instruction).to include('todo dia, das 08h às 20h')
      expect(agente.instruction).not_to include('$horarioAtendimento')
    end

    it 'usa o horario padrao quando nao informam' do
      expect(construir.instruction).to include('09h às 18h')
    end

    it 'escreve o comportamento escolhido' do
      expect(construir(comportamento: 'objetivo').instruction).to include('objetivo')
    end

    it 'recusa comportamento que nao existe' do
      expect { construir(comportamento: 'agressivo') }
        .to raise_error(described_class::ComportamentoInvalido)
    end

    it 'nao deixa agente meio-pronto quando o comportamento e invalido' do
      expect { construir(comportamento: 'agressivo') }.to raise_error(described_class::ComportamentoInvalido)
      expect(Autonomia::Agents::Agent.where(account: account)).to be_empty
    end
  end

  # TUDO OU NADA. Um agente sem especialista responde sobre seguro e não cota — e ninguém percebe
  # até um cliente pedir preço.
  describe 'quando algo falha no meio' do
    it 'nao deixa agente sem especialista no banco' do
      allow(Autonomia::Agents::Specialist).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { construir }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Autonomia::Agents::Agent.where(account: account)).to be_empty
    end
  end
end
