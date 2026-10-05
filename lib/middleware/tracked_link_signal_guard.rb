# frozen_string_literal: true

# Porta de entrada do aviso de clique das páginas (POST /l/:code/clicks, #1011). Vale para
# todo POST sob /l/, em qualquer grafia que o roteador aceite (`//l/`, `/l//`, `.json`).
#
# O Rails lê e interpreta o corpo de um POST `application/json` antes de qualquer
# before_action: a instrumentação do controller grava os parâmetros no log e o
# wrap_parameters os duplica. Para este endpoint isso é errado duas vezes: o corpo traz o
# formulário da página e os sinais da Meta (dado pessoal, não vai para o log), e o limite
# de 4096 bytes só protege se ninguém ler o corpo antes dele.
#
# Por isso, aqui, antes do Rails:
# - corpo declarado acima do limite → 413, sem ler nada;
# - o content-type passa a `text/plain`: o Rails não interpreta o corpo, e o controller lê
#   o texto cru (no máximo limite + 1 byte) e faz o parse de JSON ele mesmo, como o
#   contrato manda (docs/crm/ponte-lp-atribuicao.md, seção 2).
#
# Aninhado de propósito, como Middleware::PrecompressedViteAssets: o initializer faz
# `require` deste arquivo antes do autoload.
module Middleware # rubocop:disable Style/ClassAndModuleChildren
  class TrackedLinkSignalGuard
    MAX_BODY_BYTES = 4096
    RAW_CONTENT_TYPE = 'text/plain'

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless signal_post?(env)
      return [413, { 'Content-Type' => 'text/plain' }, []] if env['CONTENT_LENGTH'].to_i > MAX_BODY_BYTES

      env['CONTENT_TYPE'] = RAW_CONTENT_TYPE
      @app.call(env)
    end

    private

    def signal_post?(env)
      env['REQUEST_METHOD'] == 'POST' && Ctwa::TrackedLink.public_path?(env['PATH_INFO'])
    end
  end
end
