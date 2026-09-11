require 'rails_helper'

# O AGENTE DE COTAÇÃO NASCE PRONTO — ou não nasce.
#
# O que estes exemplos travam é a promessa da tela: quem clica em "Criar Agente de Cotação" recebe um
# agente que sabe cotar, com a instrução que a Autonom.ia mantém, e sem ter escrito uma linha. Um
# agente que nasce sem a ferramenta, ou sem o especialista, é pior que nenhum — ele responde sobre
# seguro e não cota.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) { create(:account) }

  # A ferramenta de cotação só entra no catálogo com o módulo ligado e conexão pronta
  # (`available_for?`) — sem isso o exemplo abaixo passaria por engano, medindo a ausência do
  # portal em vez da ligação da ferramenta.
  def conexao_pronta
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready')
  end

  # Os dois arquivos que o Builder cola no agente: o do principal e o do especialista.
  def arquivos_de_instrucao
    described_class::INSTRUCOES.glob('*.md')
  end

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

    # CONTRA O CATÁLOGO, NUNCA CONTRA A PRÓPRIA CONSTANTE. A versão anterior deste exemplo
    # comparava a lista do Builder com as strings que o Builder escreve — as duas pontas falando a
    # mesma língua errada. `consultar_produtos_disponiveis` não existe (o slug é
    # `consultar_produtos_cotacao`) e passou verde até a Lia ir ao ar sem a ferramenta.
    it 'so liga slug que existe no catalogo de nativas' do
      desconhecidos = construir.native_tool_slugs - Autonomia::Agents::Tools::Registry.slugs

      expect(desconhecidos).to be_empty
    end

    it 'liga as duas que valem para toda conversa' do
      slugs = construir.native_tool_slugs

      expect(slugs).to include('consultar_produtos_cotacao')
      expect(slugs).to include('consultar_condicoes_gerais')
    end

    # `native_tool_slugs` é o que o agente TEM; quem esconde do principal o que é do especialista é
    # o `Answerer#enabled_agent_tools`, em runtime. Ligar a cotação aqui não faz o principal cotar
    # por fora — deixá-la de fora é que APAGA a ferramenta, inclusive para o especialista.
    it 'liga tambem a de cotacao, que o especialista reserva' do
      agente = construir

      expect(agente.native_tool_slugs).to include('cotar_seguro')
      expect(agente.specialists.first.tool_slugs).to include('cotar_seguro')
    end

    it 'recusa nascer com slug fora do catalogo' do
      stub_const("#{described_class}::TODAS_AS_TOOLS", %w[cotar_seguro slug_que_nao_existe])

      expect { construir }.to raise_error(described_class::SlugDesconhecido, /slug_que_nao_existe/)
    end

    # A INSTRUÇÃO NÃO É ROTEIRO. Ela tinha 15 frases prontas entre aspas, e o modelo não se
    # inspirava nelas — recitava. A Lia mandou ao cliente "Para a placa QNX9533, qual é o CEP onde o
    # carro dorme?", que é a linha do arquivo com a placa trocada. Frase pronta na instrução sai
    # idêntica para todo cliente, e quem lê percebe que está falando com um formulário.
    #
    # `\s*` NÃO É ENFEITE. Ancorado só em `\A>`, este exemplo passava verde com duas frases
    # roteirizadas ainda vivas na §9 — citação aninhada sob item de lista vem indentada, e a guarda
    # não a enxergava. Guarda que não cobre o formato real do documento é intenção, não guarda.
    it 'nao ensina frase pronta para o cliente' do
      roteiro = arquivos_de_instrucao.flat_map { |arquivo| arquivo.read.lines.grep(/\A\s*> "/) }

      expect(roteiro).to be_empty
    end

    # A instrução DOCUMENTA as ferramentas por slug, e o slug errado ali é tão mudo quanto na
    # config: ela mandava usar `consultar_produtos_disponiveis`, que não existe.
    it 'so cita ferramenta que existe no catalogo' do
      citados = arquivos_de_instrucao.flat_map { |arquivo| arquivo.read.scan(/^### `([a-z_]+)`$/).flatten }
      desconhecidos = citados - Autonomia::Agents::Tools::Registry.slugs

      expect(citados).not_to be_empty
      expect(desconhecidos).to be_empty
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
      expect(especialista.tool_slugs).to eq(%w[consultar_placa cotar_seguro])
    end

    # O EXEMPLO QUE FALTAVA. `tool_slugs` é só uma lista de strings: ela pode citar uma ferramenta
    # que o agente não tem, e aí `Specialist#tools` devolve VAZIO — o especialista roda sem
    # ferramenta nenhuma, não cota, e ainda assim responde ao principal em prosa. Foi o que a Lia
    # fez em produção: coletou placa, CEP e CPF e anunciou uma cotação que nunca saiu. O que prova
    # o produto não é a lista, é o que ela resolve.
    it 'alcanca de verdade a ferramenta de cotacao' do
      enable_test_encryption!

      slugs = with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') do
        Autonomia::Insurance::Config.enable_for!(account)
        conexao_pronta
        construir.specialists.first.tools.map(&:slug)
      end

      expect(slugs).to include('cotar_seguro')
    end

    it 'carrega a jornada do ramo' do
      especialista = construir.specialists.find_by(slug: 'cotacao_auto')

      expect(especialista.instruction).to include('placa')
      expect(especialista.instruction).to include('apólice anterior')
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

    # SÓ O NOME DO CAMPO, NUNCA O VALOR (rodada 7 de #380, P2 do Codex): até 8b9800791f a mensagem era o
    # próprio `@comportamento`, e a porta a devolvia em `detail` — `behavior: '$nomeAgente'` voltava ao
    # cliente da API tal como veio. As outras três recusas já nomeavam o campo; esta é a quarta.
    it 'recusa comportamento fora das opcoes dizendo o campo, nunca o valor' do
      expect { construir(comportamento: '$nomeAgente') }
        .to raise_error(described_class::ComportamentoInvalido, 'comportamento') do |erro|
          expect(erro.message).not_to include('$nomeAgente')
        end
      expect(Autonomia::Agents::Agent.count).to eq(0)
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

    # UM MARCADOR RESERVADO DENTRO DE UMA ESCOLHA (rodada 6 de #380, P2 do Codex) não pode nascer: a
    # substituição é numa passada só, então `$nomeAgente` dentro do nome da corretora chegaria ao modelo
    # como o marcador literal (termo 6). A recusa diz o campo e o motivo — nunca o valor —, e nada é
    # gravado. Vale para as três escolhas de texto livre; `comportamento` é um de dois valores fixos.
    it 'recusa nome de corretora com marcador reservado dizendo o campo, nunca o valor' do
      expect { construir(nome_corretora: '$nomeAgente') }
        .to raise_error(described_class::NomeInvalido) do |erro|
          expect(erro.message).to include('corretora')
          expect(erro.message).not_to include('$nomeAgente')
        end
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'recusa nome de agente com marcador reservado' do
      expect { construir(nome_agente: 'Mia $comportamento') }.to raise_error(described_class::NomeInvalido, /agente/)
    end

    it 'recusa horário com marcador reservado' do
      expect { construir(horario: 'das 09h às 18h, $nomeAgente') }
        .to raise_error(described_class::HorarioInvalido) { |erro| expect(erro.message).not_to include('$nomeAgente') }
      expect(Autonomia::Agents::Agent.count).to eq(0)
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
