# Os motivos de recusa das ferramentas do Seguro Viagem Universal (#3211, #3246), fora de `Tools::Recusa` só pelo
# tamanho: o catálogo continua um só (`Recusa::MOTIVOS` junta este), com a mesma regra de código sem frase reprovado.
module Autonomia::Agents::Tools::MotivosDoSeguroViagem
  MOTIVOS = {
    # #3211: as falhas da Universal nas ferramentas do Seguro Viagem (`SeguroViagem::Falhas`).
    'acesso_recusado' => 'a seguradora recusou o login da corretora; o agente passa a conversa para a equipe',
    'indisponivel' => 'o sistema da seguradora não respondeu; o agente tenta uma vez e passa a conversa para a equipe',
    'pedido_invalido' => 'a seguradora não aceitou o pedido; o modelo corrige com o cliente o dado em questão',
    'sem_link' => 'a compra voltou da seguradora sem o link de pagamento; o agente passa a conversa para a equipe',
    # #3211: as recusas próprias de `cotar_seguro_viagem`.
    'cotacao_sem_conversa' => 'não há conversa para receber a cotação de viagem (Testar, Copiloto, playground)',
    'destino_invalido' => 'a seguradora não atende algum destino pedido; nada foi cotado',
    'idade_fora_do_limite' => 'nenhum plano da seguradora aceita a idade de algum viajante; nada foi guardado',
    'sem_plano' => 'a seguradora não devolveu plano para a viagem; nada foi guardado',
    # #3223: o cliente escreveu de novo antes da cotação; o turno não posta, e nada foi cotado. Só log: não é falha de
    # fora e não vai à nota da equipe (`RecusasRecentes::NA_NOTA`).
    'turno_superado' => 'uma mensagem mais nova do cliente abriu outro turno, e este não posta; a viagem não foi cotada',
    # #3211: as recusas de `detalhes_da_cotacao`, que lê a última cotação guardada da conversa.
    'sem_cotacao' => 'a conversa ainda não tem cotação de viagem guardada; o modelo cota primeiro',
    'plano_inexistente' => 'o modelo pediu um código de plano que a última cotação da conversa não tem',
    # #3211: as recusas de `gerar_proposta_seguro_viagem`; em todas, nada foi enviado à seguradora.
    'proposta_sem_conversa' => 'não há conversa para gerar a proposta de seguro viagem (Testar, Copiloto, playground)',
    'recotar' => 'a cotação é de outro dia, ou a idade real de algum viajante muda a faixa de preço; o modelo cota de novo',
    'quantidade_de_viajantes' => 'a proposta veio com um número de viajantes diferente do da cotação',
    'cep_nao_encontrado' => 'o endereço do titular não saiu pelo CEP (CEP não achado ou consulta de CEP indisponível)',
    'proposta_em_andamento' => 'outra chamada está gerando a proposta desta cotação e a espera pelo lock passou do tempo do banco',
    # #3246: as recusas de `situacao_do_pagamento` e `segunda_via_do_voucher`; o carrinho é sempre o da proposta guardada.
    'pagamento_sem_conversa' => 'não há conversa para conferir o pagamento do seguro viagem (Testar, Copiloto, playground)',
    'sem_proposta' => 'a conversa ainda não tem proposta de seguro viagem com carrinho; nada foi consultado na seguradora',
    'pagamento_pendente' => 'o pagamento da proposta ainda não aparece como feito; o voucher não existe e nada foi enviado',
    'pagamento_cancelado' => 'o pagamento da proposta aparece como cancelado na seguradora; nada foi enviado',
    # #3249: a recusa de `coberturas_dos_planos`, que lê o catálogo de coberturas sem cotar.
    'plano_fora_do_catalogo' => 'o modelo pediu um plano que o catálogo de coberturas da seguradora não tem'
  }.freeze
end
