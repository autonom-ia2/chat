import html, sys

E = html.escape
PROP = '<span class="tag tag-prop">proposta · a aprovar</span>'

FASES = [
  dict(id="F1", nome="Fundação segura", tela="Sem tela nova", mig=False,
    entrega=["Anti-loop próprio, que não se perde quando o sistema limpa o contexto entre uma ação e outra.",
             "Cada ação feita pela automação fica registrada em nome de quem a ligou.",
             "A mesma contagem de cascata vale para os três motores: Regras, etapas do CRM e o novo.",
             "O Guia só cria ou liga automação para quem tem a permissão de gerenciar automações (PR de autorização, separado).",
             "Quando uma ação move o cliente para uma etapa, o card dele é criado ou atualizado."],
    aceite=["Uma regra que muda a conversa e dispara outra regra que a muda de volta para no segundo passo, e o histórico diz por quê.",
            "Uma ação feita pela automação aparece no registro com o nome de quem a ligou, não “sistema”.",
            "Uma pessoa sem a permissão de gerenciar automações pede ao Guia “cria uma automação” e ouve que não tem acesso. Com a permissão, funciona.",
            "Mover pela automação um contato sem card cria o card na etapa certa, sem duplicar.",
            "As regras de hoje das contas 6, 16 e 17 continuam funcionando igual."],
    exemplo="A Juliana liga a automação “lead novo vai para o Rafael”. Seis meses depois, o histórico do card mostra “movido pela automação de Juliana Prado”, e não “sistema”."),
  dict(id="F2", nome="Onde guardar", tela="Sem tela nova", mig=True,
    entrega=["As 4 tabelas novas: automações, versões, execuções e registros.",
             "Uma migration, sozinha na fila."],
    aceite=["A migration sobe e desce sem erro numa cópia do banco.",
            "Salvar uma automação duas vezes cria a versão 1 e a versão 2; a versão 1 nunca muda.",
            "Toda automação nasce desligada.",
            "Os registros com mais de 30 dias são apagados sozinhos.",
            "Não podem existir duas execuções iguais ao mesmo tempo (mesma automação, mesmo cliente, mesmo gatilho)."],
    exemplo="Alguém troca o lembrete de “2 dias” para “3 dias”. Quem já estava esperando segue com o texto antigo; quem entrar depois recebe o novo."),
  dict(id="F3", nome="O motor", tela="Roda por trás", mig=False,
    entrega=["Passos esperar, esperar até, se e parar.",
             "Passo “fazer uma ação da plataforma”, liberado pela lista de ações permitidas.",
             "O arquivo que diz quais ações podem virar passo, com o CI cobrando que nenhuma fique sem classificação.",
             "Spam corta tudo.",
             "Acordar quem está esperando, a cada minuto, e checar os gatilhos de tempo, a cada hora."],
    aceite=["“Quando a conversa for resolvida, espere 1 dia e adicione a etiqueta pós-venda” roda sozinha na conta piloto.",
            "Uma ação fora da lista permitida (ex.: apagar usuário) não aparece como passo e é recusada se alguém tentar por fora.",
            "A espera sobrevive a um deploy no meio: quem estava esperando continua depois.",
            "Desligar a automação no meio de uma espera para tudo; ninguém recebe nada depois.",
            "Conversa marcada como Spam não roda nenhum passo.",
            "Erro permanente (ex.: etiqueta apagada) para aquele cliente com motivo claro; erro passageiro tenta 3 vezes.",
            "Quem ligou perdeu acesso à caixa: a automação pausa e aparece “Assumir e religar”."],
    exemplo="Conversa resolvida numa sexta. No sábado ela ganha a etiqueta “pós-venda” e entra no funil de pós-venda, sem ninguém clicar."),
  dict(id="F4", nome="Falar com pessoas", tela="Novos passos", mig=False,
    entrega=["Mandar mensagem ao cliente, com as variáveis do cliente e do card (nome, valor, etapa). O cliente recebe uma mensagem normal da empresa; só dentro da plataforma ela fica marcada como enviada pela Automação.",
             "Avisar alguém da equipe: o responsável, um time ou uma pessoa.",
             "Sem limite de quantidade: o cliente manda quantas mensagens quiser."],
    aceite=["A mensagem chega no WhatsApp do cliente com o nome dele no lugar da variável.",
            "O cliente recebe a mensagem como qualquer mensagem da empresa: nada no texto diz “Automação”. A marcação “enviada pela Automação” existe só dentro da plataforma, para a equipe saber de onde veio.",
            "Variável vazia (cliente sem nome) pula o passo e o histórico diz “faltou o nome”; nunca sai “Olá, ,” para o cliente.",
            "Fora da janela de 24 h do WhatsApp, o passo usa o caminho já validado (retorno com envio automático do modelo aprovado) ou para com o motivo; nunca falha calado. Mandar o modelo direto, fora do follow-up, ainda precisa ser confirmado (risco 6 do ADR).",
            "O aviso à equipe chega no sino do responsável, com o link da conversa."],
    exemplo="Orçamento enviado. Dois dias sem resposta: o cliente recebe “Oi, Maria, conseguiu ver a proposta do seguro auto?”. Mais 2 dias sem resposta, e o corretor recebe “Maria não respondeu à retomada”."),
  dict(id="F5", nome="A tela", tela="Tela nova", mig=False,
    entrega=["A Automação livre aprovada no protótipo da F0, agora de verdade.",
             "Lista única com as automações novas e as antigas.",
             "Editor passo a passo e receitas prontas.",
             "“Conte o que você quer”: o Guia monta a partir do texto.",
             "Ensaio (“e se acontecesse agora com este cliente?”), sem enviar nada.",
             "Histórico de cada execução.",
             "Guia e editor usam o mesmo catálogo de passos, gerado do código, para nunca ficarem diferentes.",
             "Artigo da Central atualizado."],
    aceite=["Tudo o que o Guia monta abre no editor e pode ser alterado; nada fica travado.",
            "Tudo o que o editor oferece, o Guia também sabe montar.",
            "O ensaio mostra cada passo com o valor real do cliente escolhido e não envia nada.",
            "Ligar uma automação que manda mensagem ou usa IA pede confirmação, dizendo isso e o custo.",
            "Sem <select> nativo, funciona no celular, textos em português.",
            "O CI falha se um passo novo não tiver frase em português ou tela no editor."],
    exemplo="O dono escreve “quando o lead do anúncio chegar, manda boas-vindas e passa para o Rafael”. O Guia mostra a automação pronta, ele clica em “Ensaiar com Maria”, vê exatamente o que a Maria receberia, e liga."),
  dict(id="F6", nome="Funil e card", tela="CRM", mig=False,
    entrega=["Gatilhos do card: criado, entrou ou saiu da etapa, ganhou, perdeu, arquivado, campo mudou.",
             "Tempo: “parado há X dias na etapa” e “N dias antes de uma data do card ou do contato” (ex.: vencimento da apólice, aniversário).",
             "Retorno: criar retorno com envio automático.",
             "Em Configurar › Editar funil › etapa: “Automações desta etapa”, com as antigas (selo “jeito antigo”) e as novas.",
             "No card: “Automações deste cartão”, com o que está rodando, o histórico e “Parar para este cartão”.",
             "Receitas por tipo de negócio, começando por seguros e saúde e benefícios."],
    aceite=["Card parado 3 dias em “Orçamento enviado” dispara a automação uma vez, não todo dia.",
            "“30 dias antes do vencimento” roda no fuso da conta, no dia certo.",
            "“Parar para este cartão” para só aquele card; os outros seguem.",
            "Arquivar em massa não dispara “saiu da etapa”, e a tela avisa isso.",
            "As automações de etapa de hoje continuam funcionando e aparecem no mesmo painel.",
            "Só quem pode mexer no funil cria automação de funil.",
            PROP+" Card movido pela automação não é desfeito pela IA do funil na avaliação seguinte. Hoje a IA só respeita movimento feito por pessoa. Decisão do Rodrigo: ajustar a IA do funil ou só deixar automação mover card em funil com “Mover automaticamente” desligado.",
            "Card criado pela automação respeita a trava de 30 dias do “não é negócio”: contato arquivado pela IA como fornecedor, engano ou duplicado não ganha card de novo."],
    exemplo="Corretora: 30 dias antes do vencimento da apólice, o card vai para “Renovação”, o cliente recebe a mensagem de renovação e o corretor ganha um retorno para ligar em 5 dias, se não houver resposta."),
  dict(id="F7", nome="IA como passo", tela="Novos passos", mig=False,
    entrega=["Decidir: escolhe entre vários caminhos, com “nenhum se aplica”.",
             "Extrair: tira dados da conversa (placa, CPF, data, valor) e grava no contato ou no card.",
             "Escrever: gera um texto personalizado para mandar.",
             "Resumir: resume a conversa para a equipe.",
             "Usa a chave de IA da própria conta. O custo aparece na tela e no histórico, sem teto.",
             "Testes com IA paga só rodam com orçamento combinado antes."],
    aceite=[PROP+" Com 20 conversas reais anonimizadas, o Decidir acerta o caminho em pelo menos 18 e usa “nenhum se aplica” quando é o caso, em vez de chutar.",
            "O Extrair grava o campo certo; quando o dado não está na conversa, deixa vazio e diz isso, sem inventar.",
            "O texto do Escrever passa pelo ensaio antes de ligar. "+PROP+" Opção de exigir aprovação humana antes de enviar.",
            "O histórico mostra o que a IA decidiu, por quê e quanto custou.",
            "As IAs do CRM de hoje não mudam."],
    exemplo="O cliente manda “bati o carro ontem, e agora?”. A IA decide “sinistro”, extrai a placa e a data, cria o card no funil de Sinistros e avisa o time de sinistro com um resumo de 3 linhas."),
  dict(id="F8", nome="Gatilhos extras", tela="Novos gatilhos", mig=False,
    entrega=["Recorrente: todo dia, toda semana, todo mês, no fuso da conta, agindo em cada card ou contato que atende a um filtro (ex.: perdidos há 11 meses com o motivo “fechou com outro”).",
             "Etiqueta posta ou tirada da conversa ou do contato.",
             "Mensagem que falhou na entrega (o WhatsApp recusou).",
             "Troca de responsável ou de time.",
             "Reunião marcada, remarcada ou cancelada.",
             "Webhook de saída: mandar dados para outro sistema (planilha, n8n, ERP) e usar a resposta dele nos passos seguintes."],
    aceite=["“Toda segunda às 8h” roda uma vez por segunda, no fuso da conta, mesmo com deploy no domingo.",
            "Mensagem que falhou dispara a automação, por exemplo para tentar por e-mail quando o contato tem e-mail.",
            "Trocar o responsável de uma conversa dispara o aviso ao novo responsável.",
            "O webhook de saída manda os campos escolhidos e mostra no histórico se o outro sistema respondeu.",
            "Um valor da resposta do outro sistema (ex.: número da proposta) pode ser gravado no card, e a recusa vira caminho “deu erro” com o motivo.",
            "O recorrente com filtro age em cada card ou contato que atende ao filtro naquele dia, uma vez cada.",
            "Pôr ou tirar uma etiqueta dispara a automação, e o “se” consegue perguntar se o contato tem uma etiqueta."],
    exemplo="Toda segunda às 8h, cada corretor recebe a lista dos seus cards parados há mais de 7 dias. E quando o WhatsApp recusa uma mensagem de cobrança, ela sai por e-mail e o financeiro é avisado."),
  dict(id="F9", nome="Migrar o antigo", tela="Conta a conta", mig=False, script=True,
    entrega=["Converte as Regras de automação e as automações de etapa do CRM para o motor novo, conta a conta, com o OK do Rodrigo.",
             "Backup antes. O antigo é desligado, nunca apagado.",
             "Depois de um prazo, fecha a criação de regra nova nos motores antigos."],
    aceite=["Para cada conta, um relatório antes: “estas 26 regras viram estas 26 automações”.",
            "Depois da conversão, um mês de comportamento igual: as mesmas atribuições e os mesmos retornos.",
            "Nenhuma mensagem dupla durante a troca: antigo e novo nunca ligados ao mesmo tempo para a mesma coisa.",
            "Reverter uma conta religa o antigo e desliga o novo em minutos.",
            "Ao fim, existe um motor só, e a lista mostra tudo nele."],
    exemplo="As 26 regras “caixa X vai para a dona” da conta 17 viram 26 automações novas. A dona não percebe diferença nenhuma, e passa a ver o histórico de cada atribuição."),
]

IA = {"decide": "Decidir", "extrai": "Extrair", "escreve": "Escrever", "resume": "Resumir", "lê": "Ler"}
def ia(v): return f'<span class="ia">{E(v)}</span>'
def fase(f): return f'<a class="fref" href="#{f.lower()}">{f}</a>'

import re as _re
_ns={}; exec(open(__file__.rsplit('/',1)[0]+'/exemplos20.py' if '/' in __file__ else 'exemplos20.py').read(), _ns)
EXEMPLOS=_ns['EX']
def passo_html(t):
    t=E(t)
    return _re.sub(r'\[\[(.+?)\]\]', lambda m: ia(m.group(1)), t)
PAGINAS=sorted({p for e in EXEMPLOS for p in e['paginas']})
def li_aceite(fid, i, t):
    txt = t if t.startswith(PROP) or PROP in t else E(t)
    if PROP in t and not t.startswith(PROP):
        a, b = t.split(PROP); txt = E(a) + PROP + E(b)
    elif t.startswith(PROP):
        txt = PROP + E(t[len(PROP):])
    cid = f"{fid}.{i}"
    return f'<li id="{cid.lower().replace(".","-")}"><span class="cid">{cid}</span><span class="box" aria-hidden="true"></span><span class="ctext">{txt}</span></li>'

def secao(f):
    badges = f'<span class="tag">{E(f["tela"])}</span>'
    badges += '<span class="tag tag-mig">com migration</span>' if f["mig"] else ''
    badges += '<span class="tag">escrita por script, com backup</span>' if f.get("script") else ''
    ent = "".join(f"<li>{E(x)}</li>" for x in f["entrega"])
    ac = "".join(li_aceite(f["id"], i+1, t) for i, t in enumerate(f["aceite"]))
    return f'''
<section class="fase" id="{f["id"].lower()}" aria-labelledby="t-{f["id"].lower()}">
  <header class="fase-head">
    <span class="fid">{f["id"]}</span>
    <div class="fase-tit"><h2 id="t-{f["id"].lower()}">{E(f["nome"])}</h2><div class="tags">{badges}<span class="tag tag-estado">a entregar</span></div></div>
  </header>
  <div class="fase-corpo">
    <div class="col-entrega"><h3>O que entrega</h3><ul class="entrega">{ent}</ul>
      <figure class="exemplo"><figcaption>Exemplo do dia a dia</figcaption><p>{E(f["exemplo"])}</p></figure></div>
    <div class="col-aceite"><h3>Aceite <span class="count">{len(f["aceite"])} itens</span></h3><ol class="aceite">{ac}</ol></div>
  </div>
</section>'''

def slug(x): return _re.sub(r'[^a-z0-9]+','-',x.lower().replace('ç','c').replace('ã','a').replace('á','a').replace('é','e').replace('ê','e').replace('í','i').replace('ó','o').replace('õ','o').replace('ú','u')).strip('-')
def ex(i, e):
    ps = "".join(f"<li>{passo_html(p)}</li>" for p in e["passos"])
    us = " ".join(fase(x) for x in e["usa"])
    pg = "".join(f'<span class="pg">{E(x)}</span>' for x in e["paginas"])
    conv = f'<p class="novo"><span class="lbl">Convive</span>{E(e["conv"])}</p>' if e.get("conv") else ''
    return f'''
<article class="ex" id="exemplo-{i}" data-paginas="{' '.join(slug(x) for x in e['paginas'])}">
  <header><span class="exn">{i}</span><div class="exh"><h3>{E(e["n"])}</h3><span class="neg">{E(e["neg"])}</span></div></header>
  <blockquote class="pedido"><p>“{E(e["pedido"])}”</p><cite>{E(e["quem"])}</cite></blockquote>
  <p class="quando"><span class="lbl">Começa quando</span>{E(e["gatilho"])}</p>
  <ol class="passos">{ps}</ol>
  <div class="resultado"><span class="lbl">Resultado</span><p>{E(e["resultado"])}</p></div>
  <p class="novo"><span class="lbl">Por que é novo</span>{E(e["novo"])}</p>{conv}
  <footer class="exf"><div class="pgs">{pg}</div><p class="usa"><span class="lbl">Usa</span>{us}</p></footer>
</article>'''

FILTRO = '<div class="filtro" role="group" aria-label="Filtrar por página"><button type="button" class="fb" aria-pressed="true" data-p="">Todas <span>' + str(len(EXEMPLOS)) + '</span></button>' + ''.join(
  f'<button type="button" class="fb" aria-pressed="false" data-p="{slug(p)}">{E(p)} <span>{sum(p in e["paginas"] for e in EXEMPLOS)}</span></button>' for p in PAGINAS) + '</div>'

linha = '<li class="done"><a href="#f0"><b>F0</b><span>Desenho e protótipo</span></a></li>' + "".join(
  f'<li><a href="#{f["id"].lower()}"><b>{f["id"]}</b><span>{E(f["nome"])}</span></a></li>' for f in FASES)
total = sum(len(f["aceite"]) for f in FASES)

tpl = open(sys.argv[1]).read()
out = (tpl.replace("{{LINHA}}", linha)
          .replace("{{FASES}}", "".join(secao(f) for f in FASES))
          .replace("{{EXEMPLOS}}", "".join(ex(i+1, e) for i, e in enumerate(EXEMPLOS)))
          .replace("{{TOTAL}}", str(total)).replace("{{FILTRO}}", FILTRO).replace("{{NEX}}", str(len(EXEMPLOS))))
open(sys.argv[2], "w").write(out)
print("ok", total)
