# A duração de um passo da receita (`{ valor, unidade }`, a definição `duracao` do esquema) em tempo do Rails: o
# "esperar", o prazo do "esperar até" e o "daqui" do retorno (G3). Saiu do Executor na G4 (#2628), quando ele passou do
# tamanho, com a janela do "esperar até" que depende dela.
module Autonomia::Automacao::Duracao
  UNIDADES = { 'minutos' => :minutes, 'horas' => :hours, 'dias' => :days }.freeze

  module_function

  def de(duracao) = duracao['valor'].to_i.public_send(UNIDADES.fetch(duracao['unidade']))

  # A janela do "esperar até" (G11): sem prazo gravado (a primeira conferência), de agora em diante; com ele (ao
  # retomar), do começo da espera (o prazo menos a duração dele) até o prazo.
  def janela(prazo, ate) = ate ? ((ate - de(prazo))..ate) : (Time.current..)
end
