class AddSessionPayloadToAutonomiaInsuranceConnections < ActiveRecord::Migration[7.2]
  def change
    # A SESSÃO ABERTA no portal, cifrada, guardada por conexão.
    #
    # O AGGER aceita UMA sessão viva por login: abrir outra derruba a anterior. Enquanto cada
    # chamada ao adapter fazia seu próprio login, uma cotação que consulta o resultado de poucos em
    # poucos segundos derrubava a própria sessão a cada volta, duas cotações da mesma corretora
    # brigavam, e o healthcheck da tela de Conexões matava a sessão de uma cotação em andamento.
    #
    # Aqui é o lugar certo para ela morar: é uma por conexão (conta + provider), que é exatamente o
    # escopo em que o portal a considera única. `session_expires_at` já existia e passa a ser o
    # prazo de validade real desta carga.
    #
    # `text` e não `jsonb` porque o conteúdo é CIFRADO (`encrypts` no model): é um blob opaco tanto
    # para nós quanto para o banco — só o adapter sabe o que tem dentro.
    add_column :autonomia_insurance_connections, :session_payload, :text
  end
end
