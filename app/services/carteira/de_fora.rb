# O seguro que a pessoa tem em OUTRA corretora vira lembrete (E6.5, #2899). No painel da conversa e na ficha, quem pode
# editar a pessoa solta o PDF desse seguro (ou escolhe um PDF que já chegou numa conversa dela); a plataforma lê com o
# mesmo leitor da E6, num job, e a pessoa confere o que foi lido, diz se quer o lembrete da renovação e guarda.
#
# - Carteira::DeFora::Arquivos: os PDFs das conversas da pessoa que quem pede pode ler;
# - Carteira::DeFora::Ler: guarda o arquivo numa leitura de um item só (marca `de_fora`) e põe na fila;
# - Carteira::DeFora::Andamento: o que a tela pergunta até a leitura terminar;
# - Carteira::DeFora::Guardar: o gravador do seguro de fora (ver lá por que não é o Carteira::Guardar);
# - Carteira::DeFora::Apagar: o "Desfazer" e o "Apagar este seguro", só para seguro de fora.
#
# O seguro de fora sempre pertence ao contato da tela: nada de casar pessoa pelo documento do PDF, e o telefone e o e-mail
# achados no PDF não vão para o contato (decisão P5). A rotina da renovação só cria card para ele com o lembrete aceito
# (Carteira::Renovacao::EntramHoje).
module Carteira::DeFora
  # O Guia não lê nem guarda o seguro de outra corretora por ninguém: é envio de arquivo, e o que é guardado depende do
  # que a pessoa conferiu na tela. Apagar o seguro também fica só na tela.
  SO_NA_TELA_DO_GUIA = {
    'POST relacionamentos/pessoas/:id/seguros_de_fora/leitura' => 'seguro_de_fora',
    'GET relacionamentos/pessoas/:id/seguros_de_fora/leitura/:leitura_id' => 'seguro_de_fora',
    'POST relacionamentos/pessoas/:id/seguros_de_fora' => 'seguro_de_fora',
    'DELETE relacionamentos/seguros/:id' => 'seguro_de_fora'
  }.freeze

  # A leitura de fora desta pessoa (só entre as de fora, na conta dela), ou nil.
  def self.item_da(pessoa, leitura_id)
    Carteira::LeituraItem.where(leitura_id: Carteira::Leitura.do_de_fora.select(:id))
                         .find_by(leitura_id: leitura_id, account_id: pessoa.account_id, contact_id: pessoa.id)
  end
end
