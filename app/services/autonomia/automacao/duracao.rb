# A duração de um passo da receita (`{ valor, unidade }`, a definição `duracao` do esquema) em tempo do Rails: o
# "esperar", o prazo do "esperar até" e o "daqui" do retorno (G3). Saiu do Executor na G4 (#2628), quando ele passou do
# tamanho, com a janela do "esperar até" que depende dela.
module Autonomia::Automacao::Duracao
  UNIDADES = { 'minutos' => :minutes, 'horas' => :hours, 'dias' => :days }.freeze
  # O prazo do "esperar até" que a pessoa escolheu não ter (#2750, definição `prazo_da_espera` do esquema): a espera só
  # termina pela condição. Ver EsperaNoExecutor.
  SEM_PRAZO = 'sem_prazo'.freeze

  module_function

  def sem_prazo?(prazo) = prazo == SEM_PRAZO

  # Os ids dos "esperar até" sem prazo com passos em "se vencer": esse caminho nunca rodaria. A Receita recusa ao salvar.
  def sem_prazo_que_vence(passos)
    passos.select { |passo| passo['tipo'] == 'esperar_ate' && sem_prazo?(passo['prazo']) && Array(passo['se_vencer']).any? }.pluck('id')
  end

  def de(duracao) = duracao['valor'].to_i.public_send(UNIDADES.fetch(duracao['unidade']))

  # A janela do "esperar até" (G11): sem prazo gravado (a primeira conferência), de agora em diante; com ele (ao
  # retomar), do começo da espera (o prazo menos a duração dele) até o prazo.
  def janela(prazo, ate) = ate ? ((ate - de(prazo))..ate) : (Time.current..)
end
