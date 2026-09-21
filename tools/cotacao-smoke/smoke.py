#!/usr/bin/env python3
"""Suíte de conversas do agente de cotação, contra produção.

Roda depois de cada deploy que toca o agente ou o adapter. Conversa pelo WhatsApp de teste
como um corretor conversaria e confere o resultado NO BANCO: execução criada, desfecho,
entrega e escalada. O texto da Lia não é interpretado em lugar nenhum — o que decide
aprovado ou reprovado é o dado que o produto gravou.

Uso:
    python3 smoke.py                 # todos os cenários, em sequência
    python3 smoke.py --so pj-condutor
    python3 smoke.py --listar

Configuração, toda por variável de ambiente (nenhum segredo neste diretório):
    WAHA_API_KEY      chave do WAHA            (obrigatória; costuma vir do credentials.env)
    SMOKE_WAHA_HOST   host do WAHA             (padrão https://wa-hub.autonomia.site)
    SMOKE_SESSAO      sessão WAHA do CLIENTE de teste, que manda as mensagens
                      (padrão 5511937016094)
    SMOKE_CHAT_ID     chat de destino, o WhatsApp da Lia (padrão 555196569128@c.us)
    SMOKE_INBOX       caixa da Lia no Chatwoot (padrão 57)
    SMOKE_TELEFONE    telefone do contato de teste como o Chatwoot o grava
                      (padrão +SMOKE_SESSAO). É por ele que o cenário acha a CONVERSA em
                      que caiu: a caixa da Lia atende outros corretores ao mesmo tempo.
    SMOKE_PSQL        comando que roda SQL em produção e devolve linhas
                      (padrão ~/ops/agente-cotacao/onda-a/psql-prod.sh)
    SMOKE_PLACAS      placas reais, separadas por vírgula. O portal consulta a placa de
                      verdade: placa inventada não cota, e o cenário reprovaria por um
                      motivo que não é do produto.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

AQUI = Path(__file__).resolve().parent

WAHA_HOST = os.environ.get("SMOKE_WAHA_HOST", "https://wa-hub.autonomia.site")
SESSAO = os.environ.get("SMOKE_SESSAO", "5511937016094")
CHAT_ID = os.environ.get("SMOKE_CHAT_ID", "555196569128@c.us")
INBOX = os.environ.get("SMOKE_INBOX", "57")
TELEFONE = os.environ.get("SMOKE_TELEFONE", f"+{SESSAO}")
PSQL = os.environ.get(
    "SMOKE_PSQL", str(Path.home() / "ops/agente-cotacao/onda-a/psql-prod.sh")
)
PLACAS = [p.strip().upper() for p in os.environ.get("SMOKE_PLACAS", "").split(",") if p.strip()]

# Quanto esperar. A cotação real fecha em torno de 80 segundos; o teto é folgado de
# propósito, porque estourar o prazo é FALHA e não "inconclusivo", e um teto apertado
# transformaria lentidão do portal em reprovação do nosso código.
ABERTURA_S = int(os.environ.get("SMOKE_ABERTURA_S", "180"))
DESFECHO_S = int(os.environ.get("SMOKE_DESFECHO_S", "420"))
SILENCIO_S = int(os.environ.get("SMOKE_SILENCIO_S", "120"))
ENTRE_TURNOS_S = int(os.environ.get("SMOKE_ENTRE_TURNOS_S", "25"))
# A entrega é ADIADA em pedaços pela cadeia humanizada do turno: em produção o comparativo
# chegou 120 s DEPOIS do `updated_at` da execução. Por isso ela também se espera, como todo o
# resto — conferir uma vez, sem espera, reprovaria uma entrega que estava a caminho.
ENTREGA_S = int(os.environ.get("SMOKE_ENTREGA_S", "300"))
# A mensagem do cliente tem de virar linha em `messages` antes de qualquer medição: é ela que
# diz em QUE CONVERSA o cenário caiu.
CONVERSA_S = int(os.environ.get("SMOKE_CONVERSA_S", "120"))
PASSO_S = 10

# `AgentEvent::HANDOFF_TYPES` = handed_off(1), skipped_audience(2), skipped_schedule(3). Olhar só
# o 1 deixa passar a conversa entregue a humano pela porta de engajamento — rodar a suíte fora do
# horário do agente é exatamente isso, e a suíte não veria.
HANDOFF_TYPES = (1, 2, 3)


class Falha(Exception):
    """Erro de ambiente: a suíte não conseguiu medir. Não é veredito sobre o produto."""


# ---------------------------------------------------------------- documentos sintéticos


def _digitos_verificadores(base: list[int], pesos: list[list[int]]) -> list[int]:
    numero = list(base)
    for peso in pesos:
        soma = sum(d * p for d, p in zip(numero, peso))
        resto = soma % 11
        numero.append(0 if resto < 2 else 11 - resto)
    return numero


def cpf() -> str:
    base = [random.randint(0, 9) for _ in range(9)]
    pesos = [list(range(10, 1, -1)), list(range(11, 1, -1))]
    return "".join(str(d) for d in _digitos_verificadores(base, pesos))


def cnpj() -> str:
    base = [random.randint(0, 9) for _ in range(8)] + [0, 0, 0, 1]
    pesos = [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]]
    return "".join(str(d) for d in _digitos_verificadores(base, pesos))


def com_mascara_cpf(d: str) -> str:
    return f"{d[:3]}.{d[3:6]}.{d[6:9]}-{d[9:]}"


def com_mascara_cnpj(d: str) -> str:
    return f"{d[:2]}.{d[2:5]}.{d[5:8]}/{d[8:12]}-{d[12:]}"


# Pessoas sintéticas, como os documentos. Nascimento e sexo viajam escritos na mensagem
# porque a consulta por CPF não acha quem não existe: sem eles, a Lia perguntaria — o que é
# o certo dela a fazer, e reprovaria o cenário por um motivo que não é do produto.
PESSOAS = [
    ("Patrícia Almeida", "09/11/1990", "mulher"),
    ("Ricardo Menezes", "14/02/1983", "homem"),
    ("Juliana Prado", "27/06/1988", "mulher"),
    ("Marcelo Tavares", "03/09/1979", "homem"),
]


def dados_do_cenario(indice: int) -> dict[str, str]:
    """Dado novo a cada rodada, e é obrigatório: `ToolRun#pedido_ainda_vale?` trata pedido
    igual ao das últimas 24 horas como já atendido e responde do histórico. Uma suíte que
    repetisse documentos mediria o histórico, não o deploy."""
    condutor, nascimento, sexo = PESSOAS[indice % len(PESSOAS)]
    titular, nascimento_titular, sexo_titular = PESSOAS[(indice + 1) % len(PESSOAS)]
    return {
        "cpf": com_mascara_cpf(cpf()),
        "cnpj": com_mascara_cnpj(cnpj()),
        "placa": PLACAS[indice % len(PLACAS)],
        "condutor": condutor,
        "nascimento": nascimento,
        "sexo": sexo,
        "titular": titular,
        "nascimento_titular": nascimento_titular,
        "sexo_titular": sexo_titular,
    }


# ------------------------------------------------------------------------------- portas


def sql(consulta: str) -> list[list[str]]:
    """Uma consulta de leitura em produção. Devolve linhas já partidas por coluna."""
    ambiente = {**os.environ, "PSQL_FLAGS": "-At"}
    try:
        saida = subprocess.run(
            [PSQL, consulta], capture_output=True, text=True, timeout=120, env=ambiente
        )
    except FileNotFoundError as erro:
        raise Falha(f"comando de SQL não encontrado: {PSQL}") from erro
    except subprocess.TimeoutExpired as erro:
        raise Falha("a consulta em produção não respondeu em 120s") from erro
    if saida.returncode != 0:
        raise Falha(f"consulta falhou: {saida.stderr.strip()[:300]}")
    return [linha.split("|") for linha in saida.stdout.strip().splitlines() if linha.strip()]

def um_numero(consulta: str) -> int:
    """Um número, ou erro. Devolver 0 quando a saída vem vazia é o pior que este arquivo podia
    fazer: 0 em `marcar()` faz `execucoes_novas` enxergar o histórico inteiro, e o cenário passa
    na hora por uma cotação de ontem, sem relação nenhuma com o deploy. Consulta que não devolveu
    número é a suíte cega, e a suíte cega para."""
    linhas = sql(consulta)
    bruto = linhas[0][0].strip() if linhas and linhas[0] else ""
    if not bruto.lstrip("-").isdigit():
        raise Falha(f"a consulta não devolveu número ({bruto!r}): {consulta[:120]}")
    return int(bruto)


def enviar(texto: str) -> None:
    """Manda a mensagem como o cliente. Digitação antes, porque é assim que o produto é
    exercitado de verdade: o agente junta mensagens enquanto o cliente digita."""
    chave = os.environ.get("WAHA_API_KEY")
    if not chave:
        raise Falha("WAHA_API_KEY não está no ambiente")

    def chamar(rota: str, corpo: dict) -> None:
        pedido = urllib.request.Request(
            f"{WAHA_HOST}/api/{rota}",
            data=json.dumps(corpo).encode(),
            headers={"X-Api-Key": chave, "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(pedido, timeout=30) as resposta:
                resposta.read()
        except urllib.error.URLError as erro:
            raise Falha(f"WAHA recusou {rota}: {erro}") from erro

    chamar("startTyping", {"session": SESSAO, "chatId": CHAT_ID})
    time.sleep(3)
    chamar("stopTyping", {"session": SESSAO, "chatId": CHAT_ID})
    chamar("sendText", {"session": SESSAO, "chatId": CHAT_ID, "text": texto})


# ------------------------------------------------------------------------------- marcas


@dataclass
class Marca:
    """O estado do banco imediatamente antes do cenário. Tudo depois é medido por id
    maior que estes: comparar por horário erraria com relógios diferentes."""

    mensagem: int
    execucao: int
    evento: int


def marcar() -> Marca:
    return Marca(
        mensagem=um_numero("select coalesce(max(id),0) from messages;"),
        execucao=um_numero("select coalesce(max(id),0) from autonomia_agent_tool_runs;"),
        evento=um_numero("select coalesce(max(id),0) from autonomia_agent_events;"),
    )


def conversa_do_cenario(marca: Marca) -> int | None:
    """A CONVERSA em que este cenário caiu — sem ela não há veredito honesto.

    Medir por caixa credita ao cenário o que é de outra pessoa: a caixa da Lia atende vários
    corretores, e em sete dias teve 12 conversas de 3 contatos, com 22 execuções de cotação em 9
    conversas diferentes. Um anexo do vizinho satisfaria `exige_anexo`, e a execução do vizinho
    seria lida como "a cotação abriu".

    A conversa também não pode ser fixa: o Chatwoot abre conversa NOVA quando a anterior foi
    resolvida (o contato de teste já tem 10 na caixa). Então ela é descoberta a cada cenário — é
    a conversa da primeira mensagem do contato de teste depois da marca."""

    def chegou():
        linhas = sql(
            "select m.conversation_id from messages m "
            "join conversations c on c.id = m.conversation_id "
            "join contacts ct on ct.id = c.contact_id "
            f"where c.inbox_id = {INBOX} and m.id > {marca.mensagem} and m.message_type = 0 "
            f"and ct.phone_number = '{TELEFONE}' order by m.id limit 1;"
        )
        return int(linhas[0][0]) if linhas and linhas[0][0].strip() else None

    return esperar(chegou, CONVERSA_S, "mensagem do cliente na caixa da Lia")


def execucoes_novas(marca: Marca, conversa: int) -> list[dict[str, str]]:
    linhas = sql(
        "select r.id, r.slug, r.status, coalesce(r.failure_code,'-'), r.delivered_count, "
        "r.execution_key from autonomia_agent_tool_runs r "
        f"where r.conversation_id = {conversa} and r.id > {marca.execucao} order by r.id;"
    )
    return [
        {"id": l[0], "slug": l[1], "status": l[2], "falha": l[3], "entregas": l[4], "chave": l[5]}
        for l in linhas
        if len(l) >= 6
    ]


def respostas_novas(marca: Marca, conversa: int) -> list[dict[str, str]]:
    linhas = sql(
        "select m.id, case m.message_type when 0 then 'cliente' else 'lia' end, "
        "case when exists (select 1 from attachments a where a.message_id = m.id) "
        "then 'anexo' else '-' end from messages m "
        f"where m.conversation_id = {conversa} and m.id > {marca.mensagem} "
        "and m.message_type in (0,1) and m.private = false order by m.id;"
    )
    return [{"id": l[0], "quem": l[1], "anexo": l[2]} for l in linhas if len(l) >= 3]


def entregou(marca: Marca, conversa: int, chave: str, com_anexo: bool) -> bool:
    """A entrega DESTA execução virou mensagem na conversa?

    `delivered_count` não responde isso, e o próprio produto avisa (`tools/native/base.rb`): ele
    conta QUALQUER item aceito para publicação, inclusive a pergunta pelo dado que falta. Em
    produção existem as execuções 45 e 34, `done` com `delivered_count = 1`, cuja única entrega
    foi "Para concluir sua cotação, me informe..." — nenhum anexo, nenhum preço.

    A ligação exata entre mensagem e execução é o token que o publicador carimba:
    `autonomia_async_token` começa com a `execution_key` da execução. Comparar por LIKE no texto
    da coluna (e não por `->>`) é obrigatório: em produção `content_attributes` está gravada como
    STRING JSON, e o operador de chave devolveria nulo para toda linha."""
    if not chave or not set(chave) <= set("0123456789abcdefABCDEF-"):
        raise Falha(f"execution_key fora do formato esperado: {chave!r}")
    anexo = (
        "and exists (select 1 from attachments a where a.message_id = m.id) " if com_anexo else ""
    )
    return (
        um_numero(
            "select count(*) from messages m "
            f"where m.conversation_id = {conversa} and m.id > {marca.mensagem} "
            f"and m.content_attributes::text like '%{chave}%' {anexo};"
        )
        > 0
    )


def escalou(marca: Marca, conversa: int) -> bool:
    tipos = ",".join(str(t) for t in HANDOFF_TYPES)
    return (
        um_numero(
            "select count(*) from autonomia_agent_events "
            f"where id > {marca.evento} and conversation_id = {conversa} "
            f"and event_type in ({tipos});"
        )
        > 0
    )


def esperar(condicao, limite_s: int, descricao: str):
    """Espera ativa com teto. Estourar o teto devolve o último valor visto, e quem chamou
    decide: aqui, prazo estourado é sempre FALHA, nunca resultado inconclusivo."""
    fim = time.monotonic() + limite_s
    valor = condicao()
    while not valor and time.monotonic() < fim:
        time.sleep(PASSO_S)
        valor = condicao()
    print(f"      {descricao}: {'ok' if valor else f'não aconteceu em {limite_s}s'}")
    return valor


# ----------------------------------------------------------------------------- cenários


@dataclass
class Resultado:
    cenario: str
    passou: bool
    motivos: list[str] = field(default_factory=list)
    evidencia: dict[str, object] = field(default_factory=dict)


def rodar_cotacao(marca: Marca, conversa: int, exige_anexo: bool) -> Resultado:
    def abriu():
        novas = [e for e in execucoes_novas(marca, conversa) if e["slug"] == "cotar_seguro"]
        return novas[0] if novas else None

    execucao = esperar(abriu, ABERTURA_S, "execução criada")
    if not execucao:
        return Resultado("", False, ["nenhuma execução de cotação foi criada"], {})

    def terminou():
        atual = [e for e in execucoes_novas(marca, conversa) if e["id"] == execucao["id"]]
        pronto = atual and atual[0]["status"] not in ("pending", "running")
        return atual[0] if pronto else None

    final = esperar(terminou, DESFECHO_S, "cotação concluída")
    if not final:
        return Resultado("", False, [f"execução {execucao['id']} não terminou no prazo"], {})

    motivos = []
    if final["status"] != "done":
        motivos.append(f"execução terminou em {final['status']} ({final['falha']})")

    prova = "comparativo em PDF" if exige_anexo else "entrega desta execução"
    chegou = esperar(
        lambda: entregou(marca, conversa, final["chave"], exige_anexo),
        ENTREGA_S,
        f"{prova} na conversa",
    )
    if not chegou:
        motivos.append(f"a execução terminou e o {prova} não chegou ao cliente")

    if escalou(marca, conversa):
        motivos.append("a conversa foi escalada para humano")
    return Resultado(
        "",
        not motivos,
        motivos,
        # `entregas` é o `delivered_count`, que fica como EVIDÊNCIA e não como veredito: ele conta
        # até a pergunta pelo dado que falta. Quem decide é `chegou`.
        {
            "execucao": final["id"],
            "conversa": conversa,
            "status": final["status"],
            "entregas": final["entregas"],
            "entrega_na_conversa": bool(chegou),
        },
    )


def rodar_sem_cotacao(marca: Marca, conversa: int) -> Resultado:
    """Aqui o certo é o agente conversar. Espero o silêncio de execução: se nasceu
    cotação, o cenário reprova, e a espera inteira é necessária para não aprovar cedo
    demais uma cotação que ia nascer no segundo seguinte."""
    time.sleep(SILENCIO_S)
    motivos = []
    execucoes = execucoes_novas(marca, conversa)
    if execucoes:
        quais = ", ".join(f"{e['slug']}#{e['id']}" for e in execucoes)
        motivos.append(f"abriu execução que não devia: {quais}")
    if not [m for m in respostas_novas(marca, conversa) if m["quem"] == "lia"]:
        motivos.append("o cliente ficou sem resposta")
    if escalou(marca, conversa):
        motivos.append("a conversa foi escalada para humano em vez de perguntar")
    return Resultado("", not motivos, motivos, {"execucoes": len(execucoes), "conversa": conversa})


def rodar(cenario: dict, indice: int) -> Resultado:
    print(f"\n[{cenario['id']}] {cenario['titulo']}")
    print(f"      por quê: {cenario['motivo']}")
    espera_cotacao = cenario["espera"] == "cotacao"
    exige_anexo = bool(cenario.get("exige_anexo"))
    if exige_anexo and not espera_cotacao:
        raise Falha(
            f"cenário {cenario['id']} exige anexo sem esperar cotação: não há o que entregar"
        )
    dados = dados_do_cenario(indice)
    marca = marcar()

    for numero, turno in enumerate(cenario["turnos"], start=1):
        enviar(turno.format(**dados))
        print(f"      turno {numero} enviado")
        if numero < len(cenario["turnos"]):
            time.sleep(ENTRE_TURNOS_S)

    conversa = conversa_do_cenario(marca)
    if conversa is None:
        return Resultado(
            cenario["id"],
            False,
            ["a mensagem do cliente não virou conversa na caixa da Lia"],
            {"placa": dados["placa"]},
        )

    resultado = (
        rodar_cotacao(marca, conversa, exige_anexo)
        if espera_cotacao
        else rodar_sem_cotacao(marca, conversa)
    )
    resultado.cenario = cenario["id"]
    resultado.evidencia["placa"] = dados["placa"]
    return resultado


def main() -> int:
    opcoes = argparse.ArgumentParser(description=__doc__)
    opcoes.add_argument("--so", help="roda só o cenário com este id")
    opcoes.add_argument("--listar", action="store_true", help="lista os cenários e sai")
    argumentos = opcoes.parse_args()

    cenarios = json.loads((AQUI / "cenarios.json").read_text(encoding="utf-8"))
    if argumentos.listar:
        for c in cenarios:
            print(f"{c['id']:24} {c['titulo']}")
        return 0
    # O ÍNDICE É O DO ARQUIVO, e continua sendo com `--so`: é ele que escolhe a placa e a pessoa.
    # Reindexar a lista filtrada faria `--so` rodar com placa e condutor DIFERENTES da rodada
    # cheia — justo no comando que o README manda usar para reproduzir uma falha.
    numerados = list(enumerate(cenarios))
    if argumentos.so:
        numerados = [(i, c) for i, c in numerados if c["id"] == argumentos.so]
        if not numerados:
            print(f"não existe cenário com id {argumentos.so}", file=sys.stderr)
            return 2

    if not TELEFONE.startswith("+") or not TELEFONE[1:].isdigit():
        print(
            f"SMOKE_TELEFONE precisa ser o telefone do contato de teste em formato +55…, e veio "
            f"{TELEFONE!r}. É por ele que cada cenário acha a conversa em que caiu.",
            file=sys.stderr,
        )
        return 2

    if not PLACAS:
        print(
            "SMOKE_PLACAS não está definida. O portal consulta a placa de verdade, e placa "
            "inventada reprovaria o cenário por um motivo que não é do produto.",
            file=sys.stderr,
        )
        return 2

    print(f"caixa {INBOX} · {len(numerados)} cenário(s) · cada cotação real custa consulta paga")
    resultados = []
    for indice, cenario in numerados:
        try:
            resultados.append(rodar(cenario, indice))
        except Falha as erro:
            print(f"      ambiente: {erro}", file=sys.stderr)
            resultados.append(Resultado(cenario["id"], False, [f"não deu para medir: {erro}"]))

    print("\n" + "=" * 72)
    for r in resultados:
        selo = "PASSOU" if r.passou else "FALHOU"
        print(f"{selo:7} {r.cenario:24} {r.evidencia}")
        for motivo in r.motivos:
            print(f"        {motivo}")
    reprovados = [r for r in resultados if not r.passou]
    print(f"{len(resultados) - len(reprovados)}/{len(resultados)} passaram")
    return 1 if reprovados else 0


if __name__ == "__main__":
    sys.exit(main())
