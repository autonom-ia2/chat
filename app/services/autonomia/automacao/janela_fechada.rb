# Fora da janela do canal, a execução para (#2414 F4.4, decisão do Rodrigo na #2573). A mensagem não saiu porque a
# janela está fechada e nenhum modelo aprovado saiu no lugar: seguir faria o passo seguinte esperar a resposta a uma
# mensagem que nunca saiu. Vale para o passo "mensagem" e para o "escrever" ao cliente, que para antes de pagar a IA.
# Quem sabe que a janela estava fechada é o passo (PassoDeMensagem.pulado marca `janela: fechada`); os outros motivos
# de pular seguem. Só esta execução para, com o motivo no histórico; a automação continua ligada.
module Autonomia::Automacao::JanelaFechada
  private

  def janela_fechada?(resultado) = resultado.tipo == :pulado && resultado.dados['janela'] == 'fechada'

  def parar_na_janela(passo, resultado) = encerrar(passo['id'], 'parada', resultado.motivo, 'falhou', resultado.dados)
end
