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

  # UM POR CONTA. Dois agentes de cotação seriam ligados às mesmas caixas de entrada e disputariam a
  # mesma conversa — cada um com o seu especialista e a sua sessão no portal —, e o corretor não teria
  # como saber qual respondeu.
  describe 'chamado duas vezes' do
    it 'recusa criar o segundo' do
      primeiro = construir

      expect { construir }.to raise_error(described_class::JaExiste, primeiro.id.to_s)
      expect(Autonomia::Agents::Agent.where(account: account).count).to eq(1)
    end

    it 'deixa outra conta criar o seu' do
      construir
      outra = create(:account)

      expect do
        described_class.new(account: outra, nome_agente: 'Ana', nome_corretora: 'Outra').call
      end.not_to raise_error
    end
  end

  describe 'o que a corretora escreve' do
    # `nome_agente` é limitado pela coluna (string, 255). `nome_corretora` NÃO vai para coluna
    # nenhuma — só é colado dentro da instrução —, então sem teto aqui ele estouraria o limite de
    # 50.000 do `instruction`, e o erro que chegaria a quem clicou não explicaria nada.
    it 'recusa nome de corretora longo demais' do
      expect { construir(nome_corretora: 'C' * 200) }
        .to raise_error(described_class::NomeInvalido, /corretora/)
    end

    it 'recusa nome de agente vazio' do
      expect { construir(nome_agente: '   ') }.to raise_error(described_class::NomeInvalido, /agente/)
    end

    # `gsub` com o valor como segundo argumento interpreta `\0` no texto de substituição. Um nome
    # contendo essa sequência passaria a inserir o próprio marcador de volta na instrução.
    it 'trata o nome como texto, e nao como padrao de substituicao' do
      agente = construir(nome_agente: 'Mia \0 Bot')

      expect(agente.instruction).to include('Mia \0 Bot')
      expect(agente.instruction).not_to include('$nomeAgente')
    end

    # A VARIÁVEL NÃO PODE ESTAR ENTRE CRASES no markdown. A substituição troca só o marcador, e as
    # crases sobram no texto que vai para o modelo: a Lia criada em 08/09 dizia "Você é `Lia`, e atende
    # pela corretora `Sena Negócios`" — o nome certo, com sujeira de formatação em volta. Não quebra,
    # mas é ruído num texto que a Autonom.ia mantém, e ninguém veria sem ler o banco.
    it 'nao deixa crase colada na variavel substituida' do
      agente = construir(nome_agente: 'Lia', nome_corretora: 'Sena')

      expect(agente.instruction).to include('Você é Lia, e atende pela corretora Sena')
      expect(agente.instruction).not_to include('`Lia`')
      expect(agente.instruction).not_to include('`Sena`')
    end

    # A guarda: as crases não voltam na próxima variável que alguém acrescentar.
    it 'nenhuma variavel do arquivo esta entre crases' do
      pasta = described_class::INSTRUCOES
      described_class::VARIAVEIS.each_key do |marcador|
        pasta.glob('*.md').each do |arquivo|
          expect(arquivo.read).not_to include("`#{marcador}`"),
                                      "#{arquivo.basename} tem #{marcador} entre crases"
        end
      end
    end

    it 'nao deixa nenhuma variavel sem substituir' do
      instrucao = construir.instruction

      described_class::VARIAVEIS.each_key do |marcador|
        expect(instrucao).not_to include(marcador)
      end
    end
  end
end
