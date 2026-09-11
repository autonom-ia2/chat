require 'rails_helper'

# A MEDIDA DA COTAÇÃO (entrega 7): quantas cotações e quantas SEGURADORAS foram acionadas, por
# corretora e por período.
#
# O que estes exemplos travam é o que a medida NÃO pode fazer: contar execução sem contar seguradora
# (uma cotação aciona dezessete — o teto de "8 por hora" eram até 136 consultas, e o número 8 não
# dizia nada sobre dinheiro), e mostrar um total que parece completo quando não é.
RSpec.describe Autonomia::Insurance::Medida do
  let(:account) { create(:account) }
  let(:outra_conta) { create(:account) }
  let(:agent) { agente_de(account) }
  let(:slug) { Autonomia::Agents::Tools::Native::InsuranceQuote.slug }
  # As dezessete seguradoras que o portal acionou nas TRÊS cotações reais da conta de teste, lidas
  # em 11/09/2026 por `agger quote result`: os mesmos códigos na renovação, na moto e no caminhão.
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  def agente_de(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: "Mia #{conta.id}", agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Cote.')
  end

  def conversa_de(conta)
    create(:conversation, account: conta, inbox: create(:inbox, account: conta))
  end

  def run!(handle:, conta: account, criada_em: Time.current, agente: nil)
    agente ||= conta == account ? agent : agente_de(conta)
    Autonomia::Agents::ToolRun.create!(
      account: conta, agent: agente, conversation_id: conversa_de(conta).id, slug: slug,
      status: 'done', execution_key: SecureRandom.uuid, handle: handle, created_at: criada_em
    )
  end

  def medida(conta: account, inicio: nil, fim: nil)
    described_class.new(conta: conta, inicio: inicio, fim: fim).call
  end

  describe 'os dois números' do
    # TERMO 2 — o número bate com um caso conhecido: se uma cotação acionou dezessete seguradoras, a
    # consulta diz dezessete. Não é número escolhido; é o que as três cotações reais devolveram.
    it 'conta dezessete seguradoras quando a execução acionou dezessete' do
      # Arrange
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     'entregues' => %w[1 3 4 5 7 8 11 12 19 20 26] })

      # Act
      resultado = medida

      # Assert — uma cotação, dezessete seguradoras. Os dois números, nunca um só.
      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
      expect(resultado[:seguradoras_com_preco]).to eq(11)
    end

    it 'soma as seguradoras de todas as cotações do período' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(2)
      expect(resultado[:seguradoras_acionadas]).to eq(34)
    end

    # A execução que o modelo abriu e o `start` recusou NÃO é cotação: não existe no portal e ninguém
    # paga por ela. Contá-la seria cobrar por trabalho que não houve.
    #
    # A LINHA É A REAL, a que o job grava depois da recusa: intenção anotada E `autonomia_submitted`
    # (o retorno do `start` foi registrado), sem `quote_id`. Um fixture sem a marca passava com
    # "cotação = quote_id OU submitted" — e essa versão cobra a recusa (rodada 3, MV1b).
    it 'nao conta execução que nunca virou cotação no portal' do
      run!(handle: { 'pedido' => 'faltam dados', 'motivo' => 'faltam_dados', 'faltando' => ['vehicle.plate'],
                     Autonomia::Agents::ToolRun::SUBMITTED_KEY => true, Autonomia::Agents::ToolRun::INTENCOES => 1 })

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:seguradoras_acionadas]).to be_zero
      expect(resultado[:cotacoes_sem_confirmacao]).to be_zero
    end

    # POR FERRAMENTA. Outra ferramenta assíncrona da mesma conta pode gravar `quote_id` e até uma lista
    # com o mesmo nome no handle dela: não é cotação de seguro, e somá-la cobraria a corretora por
    # outra coisa. O escopo lê o slug da ferramenta, e sem ele esta linha entraria na fatura.
    it 'nao conta execução de outra ferramenta, mesmo com quote_id e seguradoras no handle' do
      Autonomia::Agents::ToolRun.create!(
        account: account, agent: agent, conversation_id: conversa_de(account).id, slug: 'outra_ferramenta',
        status: 'done', execution_key: SecureRandom.uuid,
        handle: { 'quote_id' => 'x', 'seguradoras_acionadas' => dezessete }
      )

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:seguradoras_acionadas]).to be_zero
    end
  end

  describe 'isolamento e janela' do
    it 'nao mistura corretoras' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

      expect(medida[:cotacoes]).to eq(1)
      expect(medida[:seguradoras_acionadas]).to eq(17)
    end

    it 'respeita o periodo pedido' do
      run!(handle: { 'quote_id' => 'velha', 'seguradoras_acionadas' => dezessete }, criada_em: 40.days.ago)
      run!(handle: { 'quote_id' => 'nova', 'seguradoras_acionadas' => dezessete })

      expect(medida[:cotacoes]).to eq(1)
      expect(medida(inicio: 60.days.ago.to_date.to_s, fim: Time.zone.today.to_s)[:cotacoes]).to eq(2)
    end

    # A JANELA TEM DUAS BORDAS, e a de cima é a que vira dinheiro cobrado a mais. Setembro que a
    # operação pede termina em 30/09: a cotação de 01/10 é da fatura de outubro. Um `fim` ignorado
    # não deixa a conta vazia — ela fica MAIOR, e um número inflado numa fatura ninguém questiona.
    it 'nao conta cotação feita depois do fim da janela' do
      # Arrange — uma dentro de setembro, uma no primeiro dia de outubro.
      run!(handle: { 'quote_id' => 'setembro', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-09-15 10:00'))
      run!(handle: { 'quote_id' => 'outubro', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-10-01 09:00'))

      # Act
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      # Assert — a de outubro ficou de fora: uma cotação, dezessete seguradoras.
      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
    end

    # O PERÍODO QUE A CONSULTA USOU VOLTA NA RESPOSTA. Sem isso, quem cobra não sabe de que janela é
    # o número que está lendo — e "os últimos 30 dias" muda de significado a cada dia.
    it 'devolve os instantes exatos da janela' do
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      expect(resultado[:inicio]).to eq(Time.zone.parse('2026-09-01').beginning_of_day)
      expect(resultado[:fim]).to eq(Time.zone.parse('2026-09-30').end_of_day)
      expect(resultado[:fuso]).to eq(Time.zone.name)
    end

    # O FUSO É O DA CORRETORA. "Setembro" dela termina às 23h59 dela: sem isto, toda cotação feita
    # depois das 21h de 30/09 em São Paulo cairia na fatura de outubro — o nosso valor no lugar do
    # dela, numa conta de dinheiro. O resultado diz qual fuso usou, para ninguém adivinhar.
    it 'le as datas no fuso de relatorio da corretora' do
      # Arrange
      account.update!(reporting_timezone: 'America/Sao_Paulo')

      # Act
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      # Assert
      expect(resultado[:fuso]).to eq('America/Sao_Paulo')
      expect(resultado[:fim]).to eq(ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-30').end_of_day)
    end

    it 'cai no fuso da instalação quando a corretora nao configurou' do
      expect(medida[:fuso]).to eq(Time.zone.name)
    end

    # NENHUM VALOR NOSSO NO LUGAR DO VALOR DE QUEM PERGUNTA. Data que não se lê vira recusa dita, e
    # nunca "então são os últimos 30 dias" em silêncio — um número de cobrança de uma janela que o
    # operador não pediu é pior do que erro nenhum.
    it 'recusa data ilegivel em vez de escolher uma janela por conta propria' do
      expect { medida(inicio: 'ontem', fim: nil) }.to raise_error(described_class::PeriodoInvalido)
    end

    it 'recusa janela invertida' do
      expect { medida(inicio: '2026-09-30', fim: '2026-09-01') }.to raise_error(described_class::PeriodoInvalido)
    end

    it 'usa os ultimos trinta dias quando ninguem pede janela' do
      resultado = medida

      expect(resultado[:fim]).to be_within(1.minute).of(Time.current)
      expect(resultado[:inicio]).to be_within(1.minute).of(described_class::DIAS_PADRAO.days.ago.beginning_of_day)
    end
  end

  describe 'o que a medida NAO sabe, ela diz' do
    # A cotação existe no portal e o número de seguradoras nunca foi lido (a execução morreu antes da
    # primeira consulta, ou é anterior a esta entrega). Somar zero aqui faria o total parecer
    # completo — e o total serve para cobrar.
    it 'separa a cotação aberta cujo numero de seguradoras nao foi lido' do
      run!(handle: { 'quote_id' => 'q1' })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(2)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
      expect(resultado[:cotacoes_sem_medida]).to eq(1)
    end

    # Intenção anotada e número ausente: a cotação PODE existir no portal e não temos o id. Não entra
    # em `cotacoes` (afirmaria o que não se sabe) nem some (sumir é a mesma mentira ao contrário).
    it 'separa o envio sem confirmação' do
      run!(handle: { Autonomia::Agents::ToolRun::INTENCOES => 1 })

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:cotacoes_sem_confirmacao]).to eq(1)
    end

    it 'separa a que pode ter cotado duas vezes no portal' do
      run!(handle: { 'quote_id' => 'q1', Autonomia::Agents::ToolRun::INTENCOES => 2,
                     Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA => true,
                     'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:cotacoes_possivelmente_duplicadas]).to eq(1)
    end

    # `handle` é jsonb livre. Uma linha com forma inesperada não pode derrubar a consulta nem ser
    # contada como medida: ela é exatamente uma cotação SEM medida.
    it 'nao quebra com handle de forma inesperada' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => 'dezessete', 'entregues' => 3 })

      resultado = medida

      expect(resultado[:seguradoras_acionadas]).to be_zero
      expect(resultado[:cotacoes_sem_medida]).to eq(1)
    end
  end

  # TERMO 3 — quantas COTAÇÕES viraram proposta individual. A ferramenta é a entrega 8; os contadores
  # já existem, leem o handle e contam de verdade. Hoje são zero porque ninguém escreve a chave.
  describe 'propostas individuais (entrega 8)' do
    it 'conta zero enquanto nenhuma execução registra proposta' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })

      expect(medida[:cotacoes_com_proposta]).to be_zero
      expect(medida[:propostas_emitidas]).to be_zero
    end

    # OS CONTADORES ESTÃO LIGADOS, e não são zero escrito à mão: quando a entrega 8 gravar a chave no
    # handle (`InsuranceQuote::PROPOSTAS_KEY`, os códigos das seguradoras cuja proposta saiu), a
    # medida já conta sem mudar uma linha.
    #
    # A LINHA DA FATURA É `cotacoes_com_proposta` (o termo diz COTAÇÕES): uma cotação com duas
    # propostas é UMA cotação que virou proposta. A soma dos códigos vem em separado — somá-los na
    # coluna do termo diria "duas cotações viraram proposta" onde houve uma (rodada 3).
    it 'conta uma cotação com proposta, e duas propostas emitidas, quando saíram duas' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => %w[8 3] })

      expect(medida[:cotacoes_com_proposta]).to eq(1)
      expect(medida[:propostas_emitidas]).to eq(2)
    end

    # Lista vazia é "ainda nenhuma proposta", não "virou proposta".
    it 'nao conta cotação com lista de propostas vazia' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => [] })

      expect(medida[:cotacoes_com_proposta]).to be_zero
    end
  end

  describe '#por_conta' do
    it 'devolve uma linha por corretora, da que mais acionou para a que menos' do
      # Arrange
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete.first(3) })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

      # Act
      linhas = described_class.new(inicio: nil, fim: nil).por_conta

      # Assert
      expect(linhas.map { |linha| linha[:conta_id] }).to eq([outra_conta.id, account.id])
      expect(linhas.map { |linha| linha[:seguradoras_acionadas] }).to eq([17, 3])
    end

    it 'nao inventa linha para corretora sem execução' do
      expect(described_class.new(inicio: nil, fim: nil).por_conta).to be_empty
    end
  end

  # A conta que nunca cotou lê zero, e zero aqui é verdade — não é "não sei".
  it 'devolve zeros para a conta sem nenhuma execução' do
    expect(medida[:cotacoes]).to be_zero
    expect(medida[:conta_id]).to eq(account.id)
  end

  # A MEDIDA DE UMA CORRETORA EXIGE A CORRETORA. Sem a guarda, `call` sem conta devolve a PRIMEIRA
  # linha de `por_conta` — o número de outra corretora com o nome desta, numa conta de dinheiro.
  # Recusa dita, nunca a linha de quem passou na frente.
  it 'recusa medir uma conta sem saber qual é' do
    run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

    expect { described_class.new(inicio: nil, fim: nil).call }.to raise_error(ArgumentError)
  end

  # A medida lê a ferramenta pelo SLUG DELA. Digitá-lo aqui faria a consulta devolver zero em
  # silêncio no dia em que a ferramenta fosse renomeada — e zero é o número que ninguém questiona.
  it 'le o slug da propria ferramenta' do
    expect(described_class.slug).to eq(Autonomia::Agents::Tools::Native::InsuranceQuote.slug)
  end
end
