# ESBOÇO DO CONTRATO (#679): a frente B entrega o cadastro público (OpenCNPJ, BrasilAPI, CNPJ.ws e CNPJa). Este arquivo
# só existe para a frente C programar contra a assinatura; a integração troca pelos arquivos da frente B.
module Autonomia::Prospecting::Research::Registry
  # Falha tipada do cadastro. `code` vai para research_error do lead.
  class Error < StandardError
    def code
      message
    end
  end

  def self.fetch(_cnpj)
    raise NotImplementedError, 'frente B (#679)'
  end
end
