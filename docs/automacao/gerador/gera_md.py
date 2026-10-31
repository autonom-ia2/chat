import re, html as H, runpy, sys
import os; _d=os.path.dirname(os.path.abspath(__file__)); sys.argv=['x',os.path.join(_d,'termos_tpl.html'),'/dev/null']
g=runpy.run_path(__import__('os').path.join(__import__('os').path.dirname(__file__),'gera_termos.py'))
P=g['PROP']
def plain(x):
    x=x.replace(P,'*(Proposta, a aprovar.)* ')
    x=re.sub(r'\[\[(.+?)\]\]',r'**\1**',x)
    x=re.sub(r'<span class="ia">(.*?)</span>',r'**\1**',x); x=re.sub(r'<b>(.*?)</b>',r'**\1**',x)
    return H.unescape(re.sub(r'<[^>]+>','',x)).strip()
L=['# Automação livre · Termos de aceite das fases F1 a F9','',
'- **Épico:** #2414 · **Base:** ADR-001 (`docs/automacao/ADR-001-motor-de-automacao-livre.md`)',
'- **Página:** `docs/automacao/termos-de-aceite.html` (gerada dos mesmos dados; mudou aqui, mude lá).',
'- **Estado:** rascunho para o Rodrigo aprovar, 31/10/2026.',
'- **Como ler:** cada fase diz o que entrega, como provamos que ficou pronta (aceite) e um exemplo do dia a dia. Uma fase só é aceita quando todos os itens do aceite passam no painel, e nas contas piloto 1, 16 e 18 depois do deploy. Cada item tem código (ex.: F3.4) para o PR citar.','',
'**Regra que vale para todas as fases (Rodrigo, 31/10):** não existe teto de uso. O cliente paga e usa quanto quiser: sem limite de mensagens por conversa, de execuções por hora ou de chamadas de IA. Ficam só as proteções contra defeito: uma automação nunca dispara a si mesma em laço, Spam corta tudo e erro permanente não é repetido sem fim.','','---','']
for f in g['FASES']:
    L+=[f'## {f["id"]} · {f["nome"]}','','**O que entrega.**']+[f'- {plain(x)}' for x in f['entrega']]+['','**Aceite.**']
    L+=[f'{i}. **{f["id"]}.{i}** {plain(t)}' for i,t in enumerate(f['aceite'],1)]
    L+=['',f'**Exemplo.** {plain(f["exemplo"])}','','---','']
L+=['## Convive com as IAs do CRM, não refaz','','Confirmado com o chat Multifunnel em 31/10, na origin/main 2ad360cf5c.','',
'- **Triagem do assunto:** já é da IA de assunto, configurada por caixa. Uma triagem pela Automação livre só roda na caixa com a IA de assunto desligada.',
'- **Retomar conversa parada:** já é dos Retornos automáticos, por funil. Uma automação que fale com cliente parado só roda no funil com eles desligados.',
'- **Mover card:** a IA do funil hoje só respeita movimento feito por pessoa. Falta decidir: ajustar a IA para respeitar a automação, ou só deixar a automação mover card em funil com "Mover automaticamente" desligado (item F6.7).',
'- **As IAs do CRM não mudam de comportamento.** A Automação livre cobre o que nenhuma delas faz.','',
f'## {len(g["EXEMPLOS"])} automações que nenhuma IA do CRM faz hoje','',
'Cada exemplo começa pelo pedido como o dono do negócio fala, sem termo técnico. O Guia transforma o pedido na automação, e a pessoa confere no ensaio antes de ligar. Todos cobrem um buraco que as IAs do CRM deixam hoje e usam só o que as fases acima entregam. "Pelo modelo aprovado" = mensagem fora da janela de 24 h do WhatsApp.','',
'Cada ação vale quando o recurso estiver marcado como passo na lista de ações permitidas (F3). Aplicar SLA a uma conversa ainda não tem ação no catálogo do Guia e entra como passo nativo.','']
for i,e in enumerate(g['EXEMPLOS'],1):
    L+=[f'### {i}. {e["n"]} · {e["neg"]}','',f'> "{e["pedido"]}"  ',f'> — {e["quem"]}','',f'**Começa quando:** {e["gatilho"]}.','']
    L+=[f'{k}. {plain(p)}' for k,p in enumerate(e['passos'],1)]
    L+=['',f'**Resultado:** {e["resultado"]}','',f'**Por que é novo:** {e["novo"]}']
    if e.get('conv'): L+=['',f'**Convive:** {e["conv"]}']
    L+=['',f'*Páginas: {", ".join(e["paginas"])} · Usa: {", ".join(e["usa"])}.*','']
open(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','termos-de-aceite-F1-F9.md'),'w').write('\n'.join(L))
print('md ok')
