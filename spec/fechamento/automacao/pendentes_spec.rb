require 'rails_helper'

# Fechamento do épico #2414 (F9.6): os exemplos dos termos de aceite que ainda não rodam na main. Cada um fica pendente
# com as lacunas que o seguram (códigos G* de docs/automacao/F9-fechamento-20-exemplos.md, seção 5). Quando as lacunas
# de um exemplo fecham, ele ganha o arquivo próprio, como o exemplo 10, e sai daqui. O épico só fecha com os 20
# passando (F9.8).
RSpec.describe 'Fechamento #2414 · exemplos que ainda não rodam', type: :model do
  pendentes = {
    # O 2 saiu com o #2762 (G29), depois do #2773 (G30) e do #2800 (G32); o spec de ponta a ponta dele é o #2856.
    4 => ['Aluno que começa a faltar', 'G5 (entrou em "Faltou"), G1, G3, G4, G12, G15, G25, G28'],
    # O 5 saiu com a G47 (#2766): o spec próprio (exemplo_05_revisao_do_carro_spec.rb) roda à risca, passos 1 a 8.
    # Numa automação só (no contato, pelo aniversário), os passos 2, 3, 7 a 9 e o aviso do 6 rodam
    # (g59_reuniao_atendida_na_espera_spec.rb: G56, G59, G60, G61); a G47 não segura o passo 8, porque a espera lê a
    # reunião de qualquer card do contato. Faltam a G49 (gravar no card que a automação criou, passos 5 e 6) e a G25
    # (fechar o card, passo 10).
    6 => ['Aniversário que vira horário marcado', 'G49 (gravar no card criado), G25, G1, G4, G6, G12, G14, G16, G33, G56, G59, G60, G61'],
    7 => ['Black Friday para os clientes antigos primeiro', 'G37 (público com exclusão), G38, G39, G5, G7, G14, G15'],
    8 => ['Funcionário novo no plano da empresa', 'G24 (2ª automação em cada card criado), G1, G4, G5, G7, G13, G17, G20, G22, G27'],
    9 => ['Prospecção que roda sozinha toda semana', 'G7 (segunda às 8h), G3, G4, G12, G14, G21'],
    # O 10 saiu com o lote 4 (#2682, G40) depois da G41 (#2759): o spec dele roda à risca, com a espera só pela Fernanda.
    # O 13 saiu com o lote 2 (#2679): o spec dele roda à risca, com o card ganho e a IA lendo o card.
    11 => ['Indicação que vira presente', 'G4, G17, G18 (criar o contato e o card do amigo e agir no card dele), G1, G5, G12, G16'],
    # O 12: a espera do passo 3 está provada à risca (g48_campo_do_card_spec.rb, passos 1 a 4 e 8); falta a G25 (passo 7).
    12 => ['Visita que aconteceu decide o próximo passo', 'G48 (o campo do card acorda a espera), G5, G2, G3, G11, G14, G25, G35'],
    # O 15 saiu com o G27 (#2661) sobre o lote 4 (#2687, G40): exemplo_15_cliente_grande_spec.rb roda à risca.
    # Os passos 1 a 6 têm spec próprio à risca, numa automação só (G46): exemplo_14_documentacao_spec.rb.
    14 => ['Documentação completa para emitir', 'G13 (passos 7 e 8: mandar à seguradora e gravar a proposta; a recusa avisa a Dona Cida)'],
    16 => ['Reconquistar quem foi para o concorrente', 'G7 (todo dia 1º), G3, G4, G12, G14, G16, G18'],
    # O 17 saiu com a G66 (#2843), a G67 (#2844) e a decisão 18: exemplo_17_ferias_spec.rb roda à risca numa automação
    # só, inteiro, sem pendente (a agente de IA cobre a Renata pela opção do passo, e a conversa volta quando ela escreve).
    18 => ['Seleção de candidatos sem planilha', 'G4, G20 (ler o currículo e criar o card), G1, G5, G6, G12, G15, G25'],
    19 => ['Cliente que sumiu do WhatsApp', 'G43 (mandar ao número novo), G1, G2, G3, G8, G11, G19, G28, G34, G53'],
    20 => ['Venda fechada já entra no sistema da empresa', 'G5 (card ganho), G1, G2, G7, G11, G12, G13']
  }

  it 'sonda quebrada é erro, nunca pendente' do
    stub_const('FechamentoAutomacao::Lacunas::SONDAS', { 'GX' => -> { raise NameError, 'classe renomeada' } })

    expect { FechamentoAutomacao::Lacunas.abertas(%w[GX]) }.to raise_error(NameError)
  end

  # As sondas do 17 rodam o código de verdade; com o exemplo fora da lista, a prova delas fica aqui.
  it 'exemplo 17: as lacunas fechadas por comportamento continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G63 G64 G66 G67])).to be_empty
  end

  pendentes.each do |numero, (nome, lacunas)|
    it "exemplo #{numero}: #{nome}" do
      # Fora do `pending`: sonda quebrada (classe renomeada) é erro vermelho, não "falha esperada".
      abertas = FechamentoAutomacao::Lacunas.abertas(lacunas.split(', ').map { |lacuna| lacuna.split.first })
      pending "lacunas #{lacunas}. #{FechamentoAutomacao::Lacunas::SE_PASSOU % numero}"
      expect(abertas).to be_empty
    end
  end
end
