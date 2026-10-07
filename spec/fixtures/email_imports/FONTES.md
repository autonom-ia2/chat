# Modelos de e-mail para a suíte de fidelidade do importador (#1099)

Cada `.html` desta pasta passa por `EmailCampaigns::Import::Engine` em
`spec/services/email_campaigns/import/engine_fidelity_spec.rb`.

## Escritos para o projeto

Imitam o HTML exportado por construtores de e-mail. Usam domínios `example.com` e dados inventados.

- `brevo.html`, `hubspot.html`, `mailchimp.html`, `mailjet.html` (MJML colado como HTML), `rdstation.html`
- `feito-a-mao-hostil.html`: conteúdo hostil (script, formulário, iframe, `javascript:`, CSS perigoso)
- `produtos-vml.html`: banner com fundo em VML, botão só em VML, grade de produtos em 3 colunas,
  tabela do pedido e rodapé com endereço

## De terceiros, licença MIT

Os arquivos foram copiados sem alteração. A licença MIT exige manter o aviso de copyright, reproduzido abaixo.

| Arquivo | Origem | Copyright |
|---|---|---|
| `cerberus-hibrido.html` | github.com/emailmonday/Cerberus, `cerberus-hybrid.html` | (c) 2017 Ted Goas |
| `cerberus-responsivo.html` | github.com/emailmonday/Cerberus, `cerberus-responsive.html` | (c) 2017 Ted Goas |
| `uma-coluna-botao.html` | github.com/leemunroe/responsive-html-email-template, `email.html` | (c) 2013 Lee Munroe |
| `fatura-tabela.html` | github.com/mailgun/transactional-email-templates, `templates/billing.html` | (c) 2014 Mailgun |
| `alerta.html` | github.com/mailgun/transactional-email-templates, `templates/alert.html` | (c) 2014 Mailgun |
| `coluna-unica.html` | github.com/InterNations/antwort, `single-column/build.html` | (c) 2012-2013 InterNations GmbH |
| `duas-colunas.html` | github.com/InterNations/antwort, `two-cols-simple/build.html` | (c) 2012-2013 InterNations GmbH |
| `tres-colunas-imagens.html` | github.com/InterNations/antwort, `three-cols-images/build.html` | (c) 2012-2013 InterNations GmbH |
| `promocional.html` | github.com/konsav/email-templates, `promotional.html` | (c) 2016 Konstantin Savchenko |
| `geral.html` | github.com/konsav/email-templates, `general.html` | (c) 2016 Konstantin Savchenko |
| `exploracao.html` | github.com/konsav/email-templates, `explorational.html` | (c) 2016 Konstantin Savchenko |
| `recibo.html` | github.com/wildbit/postmark-templates, `templates-inlined/basic-full/receipt/content.html` | (c) 2015 Wildbit |
| `fatura.html` | github.com/wildbit/postmark-templates, `templates-inlined/basic-full/invoice/content.html` | (c) 2015 Wildbit |

Texto da licença MIT (vale para cada copyright acima):

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
> persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
> Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
> WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
> COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
> OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
