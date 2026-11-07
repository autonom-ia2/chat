require 'rails_helper'

# Fechamento do épico #2414 (F9.6): os exemplos dos termos de aceite que ainda não rodam na main. Cada um fica pendente
# com as lacunas que o seguram (códigos G* de docs/automacao/F9-fechamento-20-exemplos.md, seção 5). Quando as lacunas
# de um exemplo fecham, ele ganha o arquivo próprio, como o exemplo 10, e sai daqui. O épico só fecha com os 20
# passando (F9.8).
RSpec.describe 'Fechamento #2414 · exemplos que ainda não rodam', type: :model do
  pendentes = {
    1 => ['Renovação do seguro sem esquecer ninguém', 'G6 (30 dias antes do vencimento), G1, G2, G3, G8, G11, G12'],
    2 => ['Lead do anúncio atendido em 5 minutos', 'G5 (card criado pelo formulário), G1, G3, G11, G12, G14, G15'],
    4 => ['Aluno que começa a faltar', 'G5 (entrou em "Faltou"), G1, G3, G4, G12, G15, G25'],
    5 => ['Revisão do carro no tempo certo', 'G5 (card ganho), G1, G3, G6, G12, G16, G19'],
    6 => ['Aniversário que vira horário marcado', 'G6 (data de nascimento do contato), G1, G4, G12, G14, G16, G25'],
    7 => ['Black Friday para os clientes antigos primeiro', 'G7 (quinta às 9h), G5, G14, G15'],
    8 => ['Funcionário novo no plano da empresa', 'G24 (2ª automação em cada card criado), G1, G4, G5, G7, G13, G17, G20, G22, G27'],
    9 => ['Prospecção que roda sozinha toda semana', 'G7 (segunda às 8h), G3, G4, G12, G14, G21'],
    11 => ['Indicação que vira presente', 'G4, G17, G18 (criar o contato e o card do amigo e agir no card dele), G1, G5, G12, G16'],
    12 => ['Visita que aconteceu decide o próximo passo', 'G5 (entrou em "Visita feita"), G2, G3, G11, G14, G25'],
    14 => ['Documentação completa para emitir', 'G5 (entrou em "Documentação"), G1, G3, G13, G20'],
    15 => ['Cliente grande, atendimento de dono', 'G27 (card atualizado com valor acima de R$ 50 mil), G3, G5, G11, G12, G15'],
    16 => ['Reconquistar quem foi para o concorrente', 'G7 (todo dia 1º), G3, G4, G12, G14, G16, G18'],
    17 => ['Vendedora de férias, cliente bem cuidado', 'G9 (troca de responsável), G7, G11, G15, G16, G23'],
    18 => ['Seleção de candidatos sem planilha', 'G4, G20 (ler o currículo e criar o card), G1, G5, G6, G12, G15, G25'],
    19 => ['Cliente que sumiu do WhatsApp', 'G8 (mensagem que falhou), G1, G2, G3, G11, G19'],
    20 => ['Venda fechada já entra no sistema da empresa', 'G5 (card ganho), G1, G2, G7, G11, G12, G13']
  }

  it 'sonda quebrada é erro, nunca pendente' do
    stub_const('FechamentoAutomacao::Lacunas::SONDAS', { 'GX' => -> { raise NameError, 'classe renomeada' } })

    expect { FechamentoAutomacao::Lacunas.abertas(%w[GX]) }.to raise_error(NameError)
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
