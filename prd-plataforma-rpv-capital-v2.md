# PRD de Plataforma — RPV Capital v2

**Produto:** Plataforma de Antecipação de RPVs Municipais  
**Versão:** 2.0  
**Data:** Março 2026  
**Autor:** Wagner / IdeaNova  
**Stack:** Meta Cloud API + OpenRouter (multi-provider LLM) + Agent Skills + Python + AWS (ECS/Lambda/RDS)

---

## 1. Visão do Produto

Plataforma end-to-end para operação de antecipação de RPVs municipais, composta por 4 módulos integrados:

1. **Bot WhatsApp próprio** — inbound + outbound, inteligência via OpenRouter (multi-provider) + Claude Agent SDK
2. **Motor de dados** — crawlers, consulta TJSP batch, scoring, banco enriquecido
3. **Dashboard operacional** — gestão de portfólio, financeiro, alertas
4. **Portal do advogado** — self-service para parceiros

**Princípio arquitetural:** O motor de dados roda em batch (diário/semanal) e alimenta o RDS com todas as RPVs conhecidas, já enriquecidas com dados do TJSP. O bot **nunca consulta o TJSP em tempo real** — ele lê do banco pronto. Isso elimina latência na conversa e dependência de disponibilidade do ESAJ.

---

## 2. Personas

### 2.1 Credor pessoa física

**Perfil:** Dona Maria, 62 anos. Ganhou processo contra a Prefeitura de SP. RPV de R$ 25.000 expedida há 4 meses. Não sabe quando vai receber.  
**Canal:** WhatsApp exclusivamente. Não usa computador.  
**Gatilho:** Recebe mensagem proativa (outbound) ou indicação do advogado.

### 2.2 Advogado de Fazenda Pública

**Perfil:** Dr. Ricardo, 38 anos. 15 processos ativos contra a Prefeitura. Clientes ligam toda semana perguntando do pagamento.  
**Canal:** WhatsApp para contato rápido, portal web para gestão.  
**Gatilho:** Parceria com comissão por indicação.

### 2.3 Operador interno

**Perfil:** Equipe RPV Capital. Valida RPVs, executa cessões, monitora pagamentos.  
**Canal:** Dashboard web.

---

## 3. Arquitetura Geral

### 3.1 Visão por serviço AWS

```
┌─────────────────────────────────────────────────────────────────┐
│                     RPV CAPITAL — AWS                            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         MOTOR DE DADOS (batch — EventBridge + Lambda/ECS)│   │
│  │                                                          │   │
│  │  Lambda          Lambda          ECS Task                │   │
│  │  (crawler)  ──▶  (parser)   ──▶  (ESAJ batch)           │   │
│  │  EventBridge     pdfplumber      Playwright              │   │
│  │  cron 6h         extrai dados    enriquece TJSP          │   │
│  └──────────────────────────┬───────────────────────────────┘   │
│                             │                                   │
│                    RDS PostgreSQL                         │
│                     RPVs enriquecidas                           │
│                             │                                   │
│            ┌────────────────┼────────────────┐                  │
│            ▼                ▼                ▼                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  BOT         │  │  DASHBOARD   │  │  PORTAL      │         │
│  │  WhatsApp    │  │  Operacional │  │  Advogado    │         │
│  │              │  │              │  │              │         │
│  │  ECS Fargate │  │  Amplify     │  │  Amplify     │         │
│  │  (always-on) │  │  (S3+CDN)   │  │  (S3+CDN)   │         │
│  │  FastAPI     │  │  React +     │  │  React +     │         │
│  │  Claude SDK  │  │  RDS         │  │  RDS         │         │
│  │  Agent Skills│  │  Recharts    │  │              │         │
│  │  APScheduler │  │              │  │              │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              EventBridge (scheduling de jobs batch)       │   │
│  │  - Crawler Prefeitura → Lambda (cron diário 6h)          │   │
│  │  - ESAJ batch → ECS Task (cron diário 7h)                │   │
│  │  - Outbound → Lambda (cron seg-sex 9h)                   │   │
│  │  - Follow-up → Lambda (cron seg-sex 10h)                 │   │
│  │  - Relatório → Lambda (cron seg-sex 18h)                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Mapeamento componente → serviço AWS

| Componente | Serviço AWS | Justificativa |
|------------|------------|---------------|
| **Bot WhatsApp** (webhook + agente + APScheduler) | **ECS Fargate** (always-on, 0.25 vCPU, 512MB) | Sem cold start — resposta <1s no chat. APScheduler para alertas roda no mesmo processo. ~$15-25/mês |
| **ESAJ Scraper** (Playwright batch) | **ECS Task** (sob demanda via EventBridge) | Playwright precisa de browser completo — pesado demais para Lambda. Roda 1x/dia ~30min. ~$3-5/mês |
| **Crawler PDFs** (download + parse) | **Lambda** (trigger: EventBridge cron) | Leve (requests + pdfplumber), sem browser, executa em segundos. ~$0 |
| **Outbound scheduler** | **Lambda** (trigger: EventBridge cron) | Seleciona RPVs, dispara templates Meta, morre. ~$1/mês |
| **Follow-up + Relatório** | **Lambda** (trigger: EventBridge cron) | Jobs leves, agendados, sem estado. ~$0 |
| **Scheduling** (cron triggers) | **EventBridge Scheduler** | Substitui cron do sistema. Managed, sem servidor. $0 |
| **Dashboard + Portal** | **Amplify** (ou S3 + CloudFront) | React estático, deploy automático do GitHub, CDN. ~$1-5/mês |
| **Banco de dados** | **RDS PostgreSQL** (db.t4g.micro/small) | Créditos AWS disponíveis. Auth via Cognito ou custom JWT. ~$15-30/mês (coberto por créditos) |
| **Domínio** | **Route 53** | rpvcapital.com.br. ~$1/mês |
| **Container registry** | **ECR** | Imagens Docker do bot e ESAJ scraper. ~$1/mês |
| **Secrets** | **Secrets Manager** | Meta API token, OpenRouter API key, RDS credentials, JWT secret. ~$2/mês |
| **Logs** | **CloudWatch** | Logs de todos os componentes. Free tier generoso |
| **Filas (Fase 2)** | **SQS** | Só quando outbound > 500 msgs/dia. Não no MVP |

### 3.3 Custo mensal estimado (MVP)

| Serviço | Custo/mês |
|---------|-----------|
| ECS Fargate (bot always-on) | $15-25 |
| ECS Task (ESAJ batch 30min/dia) | $3-5 |
| Lambda (crawler + outbound + jobs) | $1-3 |
| EventBridge | $0 |
| Amplify / CloudFront | $1-5 |
| ECR | $1 |
| Secrets Manager | $2 |
| Route 53 | $1 |
| CloudWatch | $0 (free tier) |
| RDS PostgreSQL (db.t4g.micro) | $15-30 (créditos AWS) |
| **Total AWS** | **~$25-65/mês (~R$ 150-380)** |

### 3.4 Separação: ECS (always-on) vs Lambda (event-driven) vs ECS Task (batch pesado)

```
ECS Fargate (always-on):
├── FastAPI server (webhook Meta Cloud API)
├── Claude Agent SDK + Agent Skills + Tools
├── APScheduler (alertas internos, verificação pagamentos)
└── Sempre rodando — resposta instantânea ao credor

Lambda (event-driven via EventBridge):
├── crawler_prefeitura()    → cron 6h
├── outbound_scheduler()    → cron 9h seg-sex
├── followup_leads()        → cron 10h seg-sex
├── relatorio_diario()      → cron 18h seg-sex
└── Executa e morre — paga por invocação

ECS Task (batch pesado via EventBridge):
├── esaj_batch()            → cron 7h
├── Container com Playwright + Chromium
├── Rate limiting 4s entre consultas TJSP
└── Roda ~30min/dia — paga por tempo de execução
```

### 3.5 Por que não Lambda para tudo?

| Componente | Lambda? | Razão |
|------------|---------|-------|
| Bot WhatsApp | Não | Cold start 2-5s mata experiência de chat |
| ESAJ Playwright | Não | Chromium 1GB+ RAM, cold start ~10s, setup Docker complexo |
| Crawler PDFs | Sim | Leve, rápido, sem dependências pesadas |
| Outbound | Sim | Job pontual, sem estado, executa e morre |

### 3.6 SQS — quando adicionar (Fase 2)

No MVP com ~50 msgs/dia não precisa de fila. Adicionar SQS quando:
- Volume outbound > 500 msgs/dia
- Necessidade de retry automático em falhas de disparo Meta
- Dead letter queue para mensagens que falharam
- Processamento assíncrono de inbound se latência Claude virar gargalo

---

## 4. Módulo 1 — Bot WhatsApp (Core)

### 4.1 Stack técnico — 4 camadas

| Camada | Tecnologia | Papel |
|--------|-----------|-------|
| **Transporte** | Meta Cloud API (oficial) + FastAPI (webhook) | Envia/recebe mensagens WhatsApp |
| **Inteligência** | **OpenRouter** (multi-provider) + Claude Agent SDK | Roteamento inteligente entre providers (Anthropic, OpenAI, Mistral, etc). Fallback automático, otimização de custo |
| **Skills** | Agent Skills (agentskills.io) | Ensina o agente *como* fazer cada tarefa (conhecimento procedural) |
| **Tools** | Python functions customizadas | Executa ações concretas (consulta banco, calcula, registra) |
| **Orquestração** | APScheduler (dentro ECS) + EventBridge (batch) | Alertas internos + jobs agendados |
| **Estado** | RDS PostgreSQL (AWS, créditos) | Sessões, leads, RPVs, cessões, histórico |
| **Auth** | Cognito + JWT | Roles para dashboard/portal (admin, operador, advogado) |

### 4.1.1 OpenRouter — Multi-Provider LLM

O bot usa **OpenRouter** como camada de roteamento para modelos LLM, em vez de chamar providers diretamente. Isso permite:

- **Multi-provider:** Usar Claude (Anthropic), GPT (OpenAI), Gemini (Google), Mistral, Llama (Meta) — tudo via uma API
- **Fallback automático:** Se Anthropic estiver fora, OpenRouter roteia para outro provider transparentemente
- **Otimização de custo:** Usar modelos mais baratos para tarefas simples (FAQ, saudação) e modelos premium para tarefas complexas (análise de processo, proposta)
- **BYOK (Bring Your Own Key):** Configurar chaves próprias de cada provider para melhores preços
- **Monitoramento de custo:** Dashboard OpenRouter com custo por modelo/request

**Estratégia de modelos por tarefa:**

| Tarefa | Modelo sugerido | Custo relativo | Justificativa |
|--------|----------------|----------------|---------------|
| Acolhimento / FAQ | `mistral/mistral-small` ou `google/gemini-2.0-flash-lite` | Baixo | Respostas simples, não precisa de modelo pesado |
| Qualificação / Proposta | `anthropic/claude-sonnet-4` | Médio | Precisa de raciocínio e tool calling confiável |
| Análise de processo / Due diligence | `anthropic/claude-sonnet-4` | Médio | Precisão crítica na interpretação de dados |
| OCR de documentos (foto) | `anthropic/claude-sonnet-4` (vision) | Médio | Melhor OCR multimodal |
| Transcrição de áudio | `openai/whisper` (via OpenRouter) | Baixo | Especializado em transcrição |

**Integração com Agent SDK:**

```python
# config.py — Modelos por tarefa

MODELS = {
    "acolhimento": "mistral/mistral-small-latest",
    "qualificacao": "anthropic/claude-sonnet-4-20250514",
    "proposta": "anthropic/claude-sonnet-4-20250514",
    "objecoes": "mistral/mistral-small-latest",
    "advogado": "anthropic/claude-sonnet-4-20250514",
    "fallback": "openrouter/auto",  # OpenRouter escolhe melhor opção
}

# agent.py — Uso via OpenAI-compatible SDK

from openai import OpenAI

client = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=os.getenv("OPENROUTER_API_KEY"),
)

def processar_mensagem(mensagem: str, etapa: str, tools: list):
    model = MODELS.get(etapa, MODELS["fallback"])
    
    response = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system_prompt_com_skill},
            {"role": "user", "content": mensagem}
        ],
        tools=tools,
        extra_body={
            "provider": {
                "order": ["Anthropic", "OpenAI"],  # Prioridade
                "allow_fallbacks": True,
            }
        }
    )
    return response
```

### 4.2 Arquitetura de 3 camadas: Skills + Tools + SDK

A diferença fundamental:

- **Skills** (agentskills.io) = **conhecimento** — ensinam o agente o que fazer, quando, e como. São SKILL.md files com instruções, regras de negócio, fluxos conversacionais, tratamento de objeções. Carregadas sob demanda.
- **Tools** = **capacidade** — funções Python que o agente chama para executar ações concretas (consultar banco, calcular valor, registrar lead).
- **Claude Agent SDK** = **orquestrador** — decide qual skill carregar, qual tool chamar, e gera a resposta natural.

```
┌─────────────────────────────────────────────────────────┐
│                  Claude Agent SDK                        │
│              (orquestrador principal)                    │
│                                                         │
│  Recebe mensagem → Identifica contexto →                │
│  Carrega skill relevante → Usa tools → Responde         │
│                                                         │
├──────────────────────┬──────────────────────────────────┤
│                      │                                  │
│  SKILLS              │  TOOLS                           │
│  (agentskills.io)    │  (Python functions)              │
│                      │                                  │
│  rpv-acolhimento/    │  buscar_rpv_no_banco()           │
│    SKILL.md          │  calcular_proposta()             │
│                      │  registrar_lead()                │
│  rpv-qualificacao/   │  verificar_cessao_anterior()     │
│    SKILL.md          │  agendar_contato_humano()        │
│                      │  enviar_template_meta()          │
│  rpv-proposta/       │  buscar_faq()                    │
│    SKILL.md          │                                  │
│                      │                                  │
│  rpv-advogado/       │                                  │
│    SKILL.md          │                                  │
│                      │                                  │
│  rpv-objecoes/       │                                  │
│    SKILL.md          │                                  │
│    references/       │                                  │
│      faq.md          │                                  │
│      legal.md        │                                  │
│                      │                                  │
└──────────────────────┴──────────────────────────────────┘
```

### 4.3 Agent Skills do RPV Capital

Cada skill é um diretório com SKILL.md + recursos opcionais, seguindo o padrão agentskills.io:

**Skill 1: rpv-acolhimento**
```
.skills/rpv-acolhimento/
└── SKILL.md
```

```markdown
---
name: rpv-acolhimento
description: >-
  Use quando o credor inicia conversa pela primeira vez ou 
  quando a mensagem não se encaixa em nenhum outro contexto.
  Faz a recepção empática, identifica se é credor ou advogado,
  e direciona para o fluxo correto.
---

# Acolhimento de credores RPV

## Contexto
Você está atendendo pessoas que ganharam processos contra 
a Prefeitura de São Paulo e estão esperando pagamento de RPV.
Muitos são idosos, pessoas simples, que não entendem o processo.

## Regras
- Seja empático e use linguagem simples (nível ensino médio)
- Nunca use jargão jurídico sem explicar
- Não peça muitas informações de uma vez
- Identifique se é credor (PF/PJ) ou advogado

## Fluxo
1. Cumprimente e explique quem somos (1-2 frases)
2. Pergunte se tem um processo contra a Prefeitura
3. Se SIM → peça o número do processo → use tool buscar_rpv_no_banco
4. Se NÃO SABE → explique RPV de forma simples
5. Se ADVOGADO → mude para skill rpv-advogado

## Tom de voz
- Caloroso, não corporativo
- "A gente" em vez de "nós" 
- Evite: "prezado", "estimado", "informamos"
- Use: "pode ficar tranquilo", "vou te ajudar", "é simples"

## Exemplo de abertura
"Oi! Sou da RPV Capital. A gente ajuda pessoas que ganharam 
processo contra a Prefeitura a receber o dinheiro mais rápido, 
sem precisar ficar esperando meses. Como posso te ajudar?"
```

**Skill 2: rpv-qualificacao**
```
.skills/rpv-qualificacao/
└── SKILL.md
```

```markdown
---
name: rpv-qualificacao
description: >-
  Use quando o credor informou o número do processo e precisa
  ser qualificado. Consulta o banco, valida dados, e prepara
  para a proposta.
---

# Qualificação de RPV

## Quando usar
Credor forneceu número do processo (texto, foto ou áudio).

## Aceitar formatos variados
O credor pode mandar o número de várias formas:
- Texto direto: "0019063-75.2025.8.26.0053"
- Só números: "00190637520258260053"  
- Parcial: "19063/2025"
- Foto do documento: usar Claude Vision para extrair
- Áudio: transcrever e extrair número

## Fluxo
1. Recebe número → normaliza → tool buscar_rpv_no_banco
2. Se ENCONTRADA:
   - Confirme os dados com o credor: "Achei seu processo! 
     É uma RPV de R$ XX.XXX contra a Prefeitura de SP, certo?"
   - Se confirmar → mude para skill rpv-proposta
3. Se NÃO ENCONTRADA:
   - "Não encontrei esse processo na nossa base ainda."
   - "Vou anotar seus dados e um especialista vai verificar 
     pra você em até 24h, tá bom?"
   - tool registrar_lead(status="pendente_verificacao")
   - tool agendar_contato_humano(motivo="rpv_nao_encontrada")

## Validações
- Valor está dentro do teto de RPV? (R$ 31.667,41 em SP/2026)
- RPV já foi expedida? (tem data_expedicao no banco?)
- Já existe cessão anterior? tool verificar_cessao_anterior
```

**Skill 3: rpv-proposta**
```
.skills/rpv-proposta/
├── SKILL.md
└── references/
    └── tabela_escalonada.md
```

```markdown
---
name: rpv-proposta
description: >-
  Use quando a RPV foi validada e é hora de apresentar a 
  proposta de antecipação ao credor. Calcula valores, explica
  modelo escalonado, lida com objeções.
---

# Apresentação de proposta

## Quando usar
RPV validada no banco, credor confirmou os dados.

## Fluxo
1. tool calcular_proposta(valor, dias_desde_expedicao)
2. Apresente de forma clara e visual:
   - "Podemos te adiantar R$ XX.XXX (50% do valor) em até 48h"
   - "Quando a Prefeitura pagar, você ainda recebe um complemento"
   - Explique a tabela de complemento de forma simples
3. Pergunte: "Quer seguir com a antecipação?"

## Como explicar o modelo escalonado
NÃO diga "modelo escalonado" — é jargão.
DIGA: "Funciona assim: a gente te paga metade agora. 
Quando a Prefeitura pagar, você recebe mais um bônus. 
Quanto mais rápido ela pagar, maior o bônus."

## Tabela (simplificada para o credor)
- Prefeitura paga rápido → você recebe 90% no total
- Demora um pouco → 80%
- Demora bastante → 70%
- Demora muito → 60%
- Demora demais → fica nos 50% que já recebeu

## Se aceitar
- Colete: nome completo, CPF, banco/agência/conta (Pix)
- tool registrar_lead(proposta_aceita=True)
- tool agendar_contato_humano(motivo="fechamento", urgencia="alta")
- "Um especialista nosso vai entrar em contato em até 2h 
   pra finalizar tudo. Pode ficar tranquilo!"

## Se tiver dúvidas
Mude para skill rpv-objecoes
```

**Skill 4: rpv-objecoes**
```
.skills/rpv-objecoes/
├── SKILL.md
└── references/
    ├── faq.md
    └── legal.md
```

```markdown
---
name: rpv-objecoes
description: >-
  Use quando o credor tem dúvidas ou objeções sobre a 
  antecipação. Trata as objeções mais comuns com respostas
  empáticas e factuais.
---

# Tratamento de objeções

## Objeções mais comuns

### "É golpe?"
"Entendo sua preocupação! A cessão de crédito de RPV é 
prevista na Constituição Federal, artigo 100. É 100% legal. 
A gente faz um contrato formal que é registrado no tribunal. 
Se quiser, pode conferir com seu advogado antes de decidir."

### "Por que só 50%?"
"Porque a gente tá assumindo o risco de esperar a Prefeitura 
pagar — e como você viu, às vezes demora meses. Os 50% é o 
que você recebe amanhã, garantido. E se a Prefeitura pagar 
rápido, você ainda recebe um complemento que pode chegar 
até 90% do total."

### "Prefiro esperar"
"Claro, você tem todo direito de esperar! Só pra você ter 
uma ideia: RPVs como a sua estão demorando em média X dias 
pra serem pagas. Mas fica à vontade. Se mudar de ideia, 
é só me chamar aqui."

### "Preciso falar com meu advogado"
"Perfeito! Inclusive, se seu advogado quiser, temos um 
programa de parceria com escritórios. Posso mandar as 
informações pra ele?"

### "O valor é muito baixo"
"Entendo. Leva em conta que a Prefeitura está demorando 
em média X meses pra pagar. Se você precisa do dinheiro 
agora, os 50% hoje podem valer mais do que 100% daqui 
a 6 meses ou mais."

### "Quero falar com uma pessoa"
tool agendar_contato_humano(motivo="preferencia_humano")
"Claro! Vou pedir pra um especialista te ligar. 
Qual o melhor horário pra você?"
```

**Skill 5: rpv-advogado**
```
.skills/rpv-advogado/
└── SKILL.md
```

```markdown
---
name: rpv-advogado
description: >-
  Use quando a pessoa se identifica como advogado(a).
  Apresenta programa de parceria, comissão, e permite
  indicar clientes ou antecipar honorários próprios.
---

# Atendimento a advogados parceiros

## Tom
Mais formal que com credor PF, mas ainda acessível.
Use "Dr(a)." seguido do nome.

## Fluxo
1. "Dr(a), obrigado pelo interesse! Temos um programa de 
   parceria onde você indica RPVs dos seus clientes e 
   recebe comissão de 3 a 5% sobre o valor da operação."

2. Coleta: Nome, OAB, escritório, telefone, email
   tool registrar_lead(tipo="advogado")

3. Pergunte o que deseja:
   - [Indicar cliente] → pede número do processo → 
     fluxo normal de qualificação/proposta
   - [Antecipar meus honorários] → mesmo fluxo do credor, 
     mas identificado como honorário
   - [Saber mais sobre parceria] → explica detalhes, 
     portal do advogado (quando disponível)

## Comissão
- 3% para indicações simples
- 5% para advogado que faz a intermediação completa
- Paga quando a cessão é concluída
- Acumula e pode ser sacada mensalmente
```

### 4.4 Infraestrutura Meta Cloud API

**Setup necessário:**

1. **Meta Business Account** — conta empresarial verificada
2. **WhatsApp Business Account (WABA)** — vinculada ao Meta Business
3. **Número de telefone** — dedicado para RPV Capital, com green tick
4. **App no Meta for Developers** — para receber webhooks
5. **Templates aprovados** — mensagens pré-aprovadas para outbound

**Fluxo de mensagens:**

```
INBOUND (credor manda mensagem):
  WhatsApp → Meta Cloud API → Webhook (FastAPI) → Claude Agent SDK → resposta → Meta Cloud API → WhatsApp

OUTBOUND (nós abordamos credor):
  Scheduler (APScheduler cron) → seleciona RPVs elegíveis → monta template → Meta Cloud API → WhatsApp
  Credor responde → fluxo inbound normal
```

**Custos Meta Cloud API (referência):**

| Tipo | Custo/msg (BR) |
|------|---------------|
| Marketing (outbound templates) | ~R$ 0,50 |
| Utility (notificações) | ~R$ 0,12 |
| Service (resposta em janela 24h) | Gratuito |

### 4.5 Integração SDK + Skills + Tools

```python
# Estrutura conceitual do agente

import anthropic
from pathlib import Path

# Carrega skills do diretório
SKILLS_DIR = Path(".skills")

# Tools customizados (funções Python)
tools = [
    buscar_rpv_no_banco,      # consulta banco
    calcular_proposta,         # lógica escalonada
    registrar_lead,            # salva no banco
    verificar_cessao_anterior, # checa duplicidade
    agendar_contato_humano,    # alerta operador via WhatsApp
    enviar_template_meta,      # dispara template outbound
    buscar_faq,                # busca knowledge base
]

# O SDK descobre as skills automaticamente
# e carrega a SKILL.md relevante conforme o contexto
# da conversa — progressive disclosure:
#
# 1. Startup: só nome + description de cada skill (~50 tokens)
# 2. Triggered: carrega SKILL.md completo da skill relevante
# 3. Deep: carrega references/ se necessário

client = anthropic.Anthropic()

def processar_mensagem(telefone: str, mensagem: str):
    # Carrega sessão do banco
    sessao = carregar_sessao(telefone)
    
    # Se é resposta a outbound, injeta contexto da RPV
    rpv_contexto = ""
    if sessao.get("origem") == "outbound":
        rpv = sessao.get("rpv_data", {})
        rpv_contexto = f"""
        Contexto: Este credor foi abordado proativamente.
        RPV: {rpv.get('numero_rpv')}
        Valor: R$ {rpv.get('valor')}
        Atraso: {rpv.get('dias_atraso')} dias
        Já temos todos os dados. Não precisa perguntar número.
        """
    
    # Monta system prompt com skills
    system = montar_system_prompt(
        skills_dir=SKILLS_DIR,
        contexto_adicional=rpv_contexto,
        etapa_atual=sessao.get("etapa", "acolhimento")
    )
    
    # Chama Claude com tools
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1024,
        system=system,
        tools=tools,
        messages=sessao["historico"] + [
            {"role": "user", "content": mensagem}
        ]
    )
    
    # Processa tool calls se houver
    resposta_final = processar_response(response, tools)
    
    # Salva sessão atualizada
    salvar_sessao(telefone, sessao, response)
    
    # Envia via Meta Cloud API
    enviar_whatsapp(telefone, resposta_final)


def montar_system_prompt(skills_dir, contexto_adicional, etapa_atual):
    """
    Monta o system prompt combinando:
    1. Instruções base do RPV Capital
    2. Skill relevante para a etapa atual (carregada do SKILL.md)
    3. Contexto adicional (se outbound, dados da RPV)
    """
    base = """
    Você é o assistente da RPV Capital via WhatsApp.
    Ajuda credores que ganharam processos contra a Prefeitura 
    de São Paulo a antecipar o recebimento de suas RPVs.
    
    Use as skills disponíveis para guiar a conversa.
    Use os tools para consultar dados e executar ações.
    """
    
    # Carrega skill da etapa atual
    skill_path = skills_dir / f"rpv-{etapa_atual}" / "SKILL.md"
    skill_content = skill_path.read_text() if skill_path.exists() else ""
    
    return f"{base}\n\n{skill_content}\n\n{contexto_adicional}"
```

### 4.6 Tools do agente (Python)

```python
# Tool 1: Buscar RPV no banco (RDS PostgreSQL)
@tool
def buscar_rpv_no_banco(numero_processo: str) -> dict:
    """
    Busca um processo no banco de dados de RPVs já enriquecidas.
    Retorna dados completos se encontrado: valor, data expedição,
    prazo estimado, status de pagamento.
    
    Input: numero_processo (aceita vários formatos, normaliza)
    Output: dados da RPV ou None se não encontrada
    """
    # Normaliza número do processo (remove pontos, traços)
    # Consulta RDS
    # Retorna: {
    #   encontrada: bool,
    #   numero_rpv: str,
    #   valor: float,
    #   data_expedicao: date,
    #   dias_desde_expedicao: int,
    #   status_pagamento: str,  # pendente, pago
    #   credor: str,
    #   prazo_estimado: int  # dias
    # }


# Tool 2: Calcular proposta escalonada
@tool
def calcular_proposta(valor_rpv: float, dias_desde_expedicao: int) -> dict:
    """
    Calcula a proposta de antecipação usando modelo escalonado.
    
    Output: {
      valor_adiantamento: float,     # 50% do valor
      tabela_complemento: [
        {prazo: "até 60 dias", complemento: "40%", total_credor: "90%"},
        {prazo: "61-90 dias", complemento: "30%", total_credor: "80%"},
        ...
      ],
      prazo_estimado: int,
      complemento_provavel: float,   # baseado no prazo estimado
      total_provavel_credor: float
    }
    """


# Tool 3: Registrar lead
@tool
def registrar_lead(
    nome: str,
    telefone: str,
    numero_processo: str,
    tipo: str,  # credor_pf, credor_pj, advogado
    valor_rpv: float,
    origem: str,  # inbound, outbound, parceiro
    proposta_aceita: bool = False
) -> dict:
    """Registra lead no banco com status 'novo'."""


# Tool 4: Verificar cessão anterior
@tool  
def verificar_cessao_anterior(numero_processo: str) -> dict:
    """
    Verifica no banco se já existe cessão registrada 
    para este processo.
    """


# Tool 5: Agendar contato humano
@tool
def agendar_contato_humano(
    telefone: str,
    motivo: str,
    urgencia: str = "normal"
) -> dict:
    """
    Agenda handoff para operador humano.
    Envia alerta via WhatsApp para o operador.
    """


# Tool 6: Buscar FAQ
@tool
def buscar_faq(pergunta: str) -> str:
    """
    Busca resposta na knowledge base para perguntas 
    frequentes sobre cessão, legalidade, prazos, etc.
    """
```

### 4.5 Fluxo conversacional — Inbound (credor)

```
ENTRADA: Credor manda mensagem para o número do RPV Capital
(via wa.me link, QR code, indicação de advogado, resposta a outbound)

AGENTE: Acolhimento
├── "Olá! Sou da RPV Capital. Ajudamos pessoas que ganharam 
│    processos contra a Prefeitura a receber mais rápido."
├── "Você tem um processo para antecipar?"
│
├── [Sim] → Pede número do processo
│   ├── Credor manda número (texto, foto, áudio)
│   │   ├── Se texto: normaliza e busca no banco
│   │   ├── Se foto: Claude Vision extrai número → busca
│   │   └── Se áudio: transcreve → extrai número → busca
│   │
│   ├── TOOL: buscar_rpv_no_banco(numero)
│   │
│   ├── [Encontrada no banco]
│   │   ├── "Encontrei seu processo! Aqui estão os dados:"
│   │   ├── Mostra: valor, data expedição, dias de atraso
│   │   ├── TOOL: calcular_proposta(valor, dias)
│   │   ├── "Podemos adiantar R$ XX.XXX (50%) em até 48h"
│   │   ├── Explica modelo escalonado
│   │   │
│   │   ├── [Aceita] → Coleta dados pessoais
│   │   │   ├── Nome completo, CPF
│   │   │   ├── Dados bancários (para depósito)
│   │   │   ├── TOOL: registrar_lead(proposta_aceita=True)
│   │   │   ├── TOOL: agendar_contato_humano("fechamento")
│   │   │   └── "Nosso especialista vai entrar em contato 
│   │   │        em até 2h para finalizar!"
│   │   │
│   │   ├── [Dúvidas] → TOOL: buscar_faq(pergunta)
│   │   │   ├── Responde dúvida
│   │   │   └── Volta para proposta
│   │   │
│   │   └── [Não agora] → TOOL: registrar_lead(proposta_aceita=False)
│   │       └── "Sem problemas! Posso te avisar quando 
│   │            a Prefeitura pagar seu RPV?"
│   │
│   └── [Não encontrada no banco]
│       ├── "Não encontrei seu processo na nossa base ainda."
│       ├── "Vou encaminhar para um especialista verificar."
│       ├── TOOL: registrar_lead(tipo="pendente_verificacao")
│       ├── TOOL: agendar_contato_humano("rpv_nao_encontrada")
│       └── Operador consulta TJSP manualmente depois
│
├── [Não sei o que é RPV]
│   ├── Explica de forma simples o que é RPV
│   ├── "Você ganhou algum processo contra a Prefeitura?"
│   └── Retoma fluxo
│
└── [Sou advogado]
    ├── "Dr(a), temos um programa de parceria!"
    ├── Coleta: Nome, OAB, escritório
    ├── Explica comissão (3-5%)
    ├── TOOL: registrar_lead(tipo="advogado")
    │
    ├── [Indicar cliente]
    │   ├── Pede número do processo do cliente
    │   └── Mesmo fluxo de busca/proposta
    │
    └── [Antecipar honorários]
        └── Mesmo fluxo do credor
```

### 4.6 Fluxo Outbound (abordagem proativa)

```
PREPARAÇÃO (batch, antes do contato):

1. Crawler identifica RPVs pendentes no banco:
   - Valor > R$ 15.000
   - Dias desde expedição > 60
   - Status: pendente (não paga)
   - Sem cessão anterior registrada

2. Para cada RPV elegível, prepara contexto:
   - Número do processo
   - Nome do credor
   - Valor da RPV
   - Dias de atraso
   - Proposta calculada

3. Agrupa por prioridade:
   - Alta: valor > R$ 25k E atraso > 120 dias
   - Média: valor > R$ 20k E atraso > 90 dias
   - Baixa: valor > R$ 15k E atraso > 60 dias

DISPARO (via Meta Cloud API templates):

4. Template aprovado pela Meta:
   
   "Olá {{nome}}! Identificamos que você tem um 
   crédito de R$ {{valor}} contra a Prefeitura de 
   São Paulo (processo {{processo_resumido}}).
   
   Sabia que podemos adiantar parte desse valor 
   em até 48 horas?
   
   Quer saber mais?
   [Sim, quero saber] [Não tenho interesse]"

5. Regras de disparo:
   - Máximo 50 templates/dia (início, escalar gradual)
   - Horário: 9h-18h dias úteis
   - Não repetir contato em 30 dias
   - Respeitar opt-out imediato

6. Credor responde → entra no fluxo inbound com contexto
   (bot já sabe qual RPV, não precisa perguntar número)
```

### 4.7 Servidor webhook (FastAPI)

```python
# Estrutura do servidor que recebe mensagens da Meta

from fastapi import FastAPI, Request
from anthropic import Agent

app = FastAPI()

@app.get("/webhook")
async def verify_webhook(request: Request):
    """Verificação do webhook pela Meta (setup inicial)."""
    # Valida hub.verify_token
    # Retorna hub.challenge

@app.post("/webhook") 
async def receive_message(request: Request):
    """Recebe mensagens do WhatsApp via Meta Cloud API."""
    body = await request.json()
    
    for entry in body.get("entry", []):
        for change in entry.get("changes", []):
            value = change.get("value", {})
            
            if "messages" in value:
                for message in value["messages"]:
                    telefone = message["from"]
                    
                    # Carrega contexto da conversa do banco
                    contexto = await carregar_sessao(telefone)
                    
                    # Extrai conteúdo (texto, imagem, áudio)
                    conteudo = await extrair_conteudo(message)
                    
                    # Processa com Claude Agent SDK
                    resposta = await rpv_agent.run(
                        messages=contexto.historico + [
                            {"role": "user", "content": conteudo}
                        ],
                        context={
                            "telefone": telefone,
                            "rpv_contexto": contexto.rpv_data,
                            "etapa": contexto.etapa
                        }
                    )
                    
                    # Salva contexto atualizado
                    await salvar_sessao(telefone, resposta)
                    
                    # Envia resposta via Meta Cloud API
                    await enviar_mensagem_whatsapp(
                        telefone, 
                        resposta.content
                    )

async def enviar_mensagem_whatsapp(telefone: str, texto: str):
    """Envia mensagem via Meta Cloud API."""
    # POST https://graph.facebook.com/v21.0/{phone_number_id}/messages
    # Headers: Authorization: Bearer {access_token}
    # Body: {
    #   messaging_product: "whatsapp",
    #   to: telefone,
    #   type: "text",
    #   text: { body: texto }
    # }

async def enviar_template_whatsapp(telefone: str, template: str, params: dict):
    """Envia template aprovado via Meta Cloud API (outbound)."""
    # POST https://graph.facebook.com/v21.0/{phone_number_id}/messages
    # Body: {
    #   messaging_product: "whatsapp",
    #   to: telefone,
    #   type: "template",
    #   template: {
    #     name: template,
    #     language: { code: "pt_BR" },
    #     components: [{ type: "body", parameters: params }]
    #   }
    # }
```

### 4.8 Templates Meta (precisam aprovação)

**Template 1 — Outbound inicial (marketing)**
```
Nome: rpv_antecipacao_inicial
Categoria: Marketing
Idioma: pt_BR

Corpo:
Olá {{1}}! Identificamos que você tem um crédito de 
R$ {{2}} contra a Prefeitura de São Paulo.

Sabia que podemos adiantar parte desse valor em até 
48 horas, sem burocracia?

Botões:
[Quero saber mais] [Não tenho interesse]
```

**Template 2 — Follow-up (utility)**
```
Nome: rpv_followup
Categoria: Utility

Corpo:
{{1}}, sua RPV de R$ {{2}} ainda está pendente de 
pagamento pela Prefeitura ({{3}} dias de atraso).

Podemos adiantar R$ {{4}} agora. Quer conversar?

Botões:
[Sim] [Já recebi] [Não]
```

**Template 3 — Alerta de pagamento (utility)**
```
Nome: rpv_pagamento_detectado
Categoria: Utility

Corpo:
{{1}}, identificamos que a Prefeitura processou o 
pagamento do seu RPV nº {{2}}!

Valor: R$ {{3}}
Data: {{4}}

Se você antecipou conosco, o complemento será 
calculado e depositado em até 48h.

Botões:
[Ver detalhes] [Falar com atendente]
```

**Template 4 — Para advogados (marketing)**
```
Nome: rpv_advogado_parceria
Categoria: Marketing

Corpo:
Dr(a). {{1}}, identificamos {{2}} RPVs elegíveis para 
antecipação na Vara da Fazenda Pública de SP.

Valor total: R$ {{3}}

Nosso programa de parceria paga {{4}}% de comissão 
por indicação. Quer saber mais?

Botões:
[Ver RPVs disponíveis] [Saber sobre parceria]
```

---

## 5. Módulo 2 — Motor de Dados (Batch)

### 5.1 Pipeline

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ CRON     │    │ DOWNLOAD │    │ PARSE    │    │ ENRIQUECE│
│ APSched  │───▶│ PDFs     │───▶│ pdfplumber│──▶│ ESAJ     │
│ 6h/dia   │    │ Prefeit. │    │ → CSV    │    │ batch    │
└──────────┘    └──────────┘    └──────────┘    └────┬─────┘
                                                     │
                                                     ▼
                                              ┌──────────┐
                                              │ RDS      │
                                              │ RPVs     │
                                              │ prontas  │
                                              └──────────┘
```

### 5.2 Crawler da Prefeitura

**Frequência:** Quinzenal (acompanha publicação dos lotes).  
**Trigger:** APScheduler cron (diário 6h) + verificação de novos lotes na página.

**Pipeline Python:**

```python
# 01_crawler_prefeitura.py

import requests
from bs4 import BeautifulSoup
import pdfplumber
import re

BASE_URL = "https://prefeitura.sp.gov.br/web/procuradoria_geral/w/lista-dos-processamentos-de-pagamentos-rpv"

def descobrir_novos_pdfs():
    """Scrape página-índice, compara com já baixados."""
    html = requests.get(BASE_URL).text
    soup = BeautifulSoup(html, "html.parser")
    links = [a["href"] for a in soup.find_all("a") if "lote" in a["href"].lower()]
    ja_baixados = carregar_lista_baixados()  # do banco
    return [l for l in links if l not in ja_baixados]

def parsear_pdf(filepath: str) -> list[dict]:
    """Extrai registros de pagamento do PDF."""
    registros = []
    with pdfplumber.open(filepath) as pdf:
        for page in pdf.pages:
            texto = page.extract_text()
            # Regex para extrair campos:
            # - Data de Vencimento
            # - Credor
            # - Valor da OE
            # - Complemento (contém RPV nº e processo)
            matches = re.findall(PATTERN_RPV, texto)
            for m in matches:
                registros.append({
                    "data_pagamento": parse_date(m[0]),
                    "credor": m[1].strip(),
                    "valor": parse_decimal(m[2]),
                    "numero_rpv": extrair_numero_rpv(m[3]),
                    "numero_processo": normalizar_processo(m[4]),
                    "cpf_cnpj": extrair_cpf(m[3]),
                    "status": m[5]  # aceito/rejeitado
                })
    return registros

def normalizar_processo(raw: str) -> str:
    """
    Converte 19 dígitos truncados para formato CNJ 20 dígitos.
    Descoberta: adicionar '3' ao final (Vara Fazenda 0053).
    Ex: 0019063752025826005 → 00190637520258260053
    Formato CNJ: 0019063-75.2025.8.26.0053
    """
    if len(raw) == 19:
        raw = raw + "3"
    # Formata CNJ
    return f"{raw[:7]}-{raw[7:9]}.{raw[9:13]}.{raw[13]}.{raw[14:16]}.{raw[16:20]}"
```

### 5.3 Enriquecimento ESAJ (batch)

**Frequência:** Roda após cada parse de novos PDFs.  
**Rate limiting:** 1 consulta a cada 4 segundos (já validado — 98.4% sucesso).

```python
# 02_enriquecimento_esaj.py

from playwright.async_api import async_playwright

async def consultar_tjsp(numero_processo_cnj: str) -> dict:
    """
    Consulta ESAJ para extrair data de expedição da RPV.
    Busca movimentação: "Ofício Requisitório-Pequeno Valor Expedido"
    """
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        # Acessa ESAJ
        await page.goto("https://esaj.tjsp.jus.br/cpopg/open.do")
        
        # Preenche campos
        partes = parse_cnj(numero_processo_cnj)
        await page.fill("#numeroDigitoAnoUnificado", partes["numero_ano"])
        await page.fill("#foroNumeroUnificado", partes["foro"])
        await page.click("#botaoConsultarProcessos")
        
        # Espera resultado
        await page.wait_for_selector("#tabelaTodasMovimentacoes")
        
        # Extrai movimentações
        movimentacoes = await page.query_selector_all("tr.containerMovimentacao")
        
        data_expedicao = None
        for mov in movimentacoes:
            texto = await mov.inner_text()
            if "Ofício Requisitório-Pequeno Valor Expedido" in texto:
                data_str = await mov.query_selector("td.dataMovimentacao")
                data_expedicao = parse_date(await data_str.inner_text())
                break
        
        # Extrai partes (para validar credor)
        partes_processo = await extrair_partes(page)
        
        await browser.close()
        
        return {
            "numero_processo": numero_processo_cnj,
            "data_expedicao": data_expedicao,
            "partes": partes_processo,
            "consultado_em": datetime.now()
        }

async def enriquecer_batch(novos_registros: list[dict]):
    """Enriquece lista de registros com dados do TJSP."""
    for registro in novos_registros:
        resultado = await consultar_tjsp(registro["numero_processo"])
        
        if resultado["data_expedicao"]:
            # Calcula prazo real
            prazo = (registro["data_pagamento"] - resultado["data_expedicao"]).days
            
            # Salva no banco
            await db.table("expedicao_rpv").upsert({
                "numero_processo": registro["numero_processo"],
                "data_expedicao": resultado["data_expedicao"],
                "prazo_dias": prazo,
                "partes": resultado["partes"]
            })
        
        # Rate limiting
        await asyncio.sleep(4)
```

### 5.4 Scoring de risco

```python
# 03_scoring.py

def calcular_score(rpv: dict) -> dict:
    """
    Score de 0-100 para cada RPV.
    Quanto maior, mais atrativa para compra.
    """
    score = 0
    alertas = []
    
    # Valor dentro do teto (R$ 31.667,41 em SP/2026)
    if rpv["valor"] > 31667.41:
        return {"score": 0, "recomendacao": "rejeitar", 
                "alertas": ["Valor acima do teto de RPV"]}
    
    # Valor atrativo (ticket mínimo viável)
    if rpv["valor"] >= 20000: score += 25
    elif rpv["valor"] >= 15000: score += 15
    elif rpv["valor"] >= 10000: score += 5
    else: alertas.append("Ticket baixo")
    
    # Dias de atraso (mais atraso = mais margem)
    dias = rpv.get("dias_desde_expedicao", 0)
    if dias > 150: score += 30
    elif dias > 90: score += 25
    elif dias > 60: score += 15
    else: score += 5
    
    # Município (SP = AAA)
    if rpv.get("municipio") == "São Paulo": score += 20
    
    # Sem cessão anterior
    if not rpv.get("cessao_anterior"): score += 15
    else: return {"score": 0, "recomendacao": "rejeitar",
                  "alertas": ["Cessão anterior existente"]}
    
    # Sem pendências
    if not rpv.get("pendencias"): score += 10
    else: alertas.append("Verificar pendências")
    
    # Classificação
    if score >= 70: recomendacao = "comprar"
    elif score >= 40: recomendacao = "avaliar"
    else: recomendacao = "baixa_prioridade"
    
    return {
        "score": score,
        "classificacao": recomendacao,
        "prazo_estimado": estimar_prazo(rpv),
        "margem_esperada": calcular_margem_esperada(dias),
        "alertas": alertas
    }
```

---

## 6. Módulo 3 — Dashboard Operacional

### 6.1 Telas principais

**Home:** Cards de métricas (carteira, capital livre, lucro, RPVs ativas) + alertas + pipeline de leads + gráfico de distribuição por prazo.

**Portfólio:** Tabela de todas as RPVs em carteira com filtros (status, valor, prazo). Click para detalhes (dados TJSP, contrato, cálculo complemento, timeline).

**Financeiro:** Fluxo de caixa (entradas/saídas), métricas de performance (margem média, ROI, giros), projeções.

**Leads/CRM:** Pipeline Kanban (novo → qualificado → proposta → aceito → cessão → finalizado). Integrado com conversas do WhatsApp.

**Outbound:** Lista de RPVs elegíveis para abordagem proativa. Status de disparo. Métricas de conversão por template.

**Templates Meta:** Gerenciamento de templates WhatsApp aprovados pela Meta (ver seção 6.4).

### 6.2 Stack

| Componente | Tecnologia |
|------------|-----------|
| Frontend | React + Tailwind + shadcn/ui |
| Auth | AWS Cognito + JWT (roles: admin, operador, advogado) |
| API | FastAPI (mesmo do bot) ou API Gateway + Lambda |
| Banco | RDS PostgreSQL |
| Gráficos | Recharts |
| Deploy | Amplify (S3 + CloudFront) |

### 6.3 Roles e Permissões (RBAC)

| Role | Acesso | Descrição |
|------|--------|-----------|
| **Admin** | Tudo | Wagner + sócio. Acesso total: financeiro, configurações, templates, usuários, dados sensíveis (CPFs, valores de cessão) |
| **Operador** | Operação | Equipe interna. Vê leads, portfólio, outbound. Pode qualificar leads, registrar cessões, aprovar propostas. Não vê dados financeiros consolidados nem configurações |
| **Analista** | Leitura | Acesso read-only a portfólio e leads. Para due diligence e análise. Não vê CPFs completos (mascarados: \*\*\*.456.789-\*\*) |
| **Advogado** | Portal parceiro | Acesso apenas ao Portal do Advogado. Vê só suas indicações e comissões. Não acessa dashboard interno |

**Implementação:**

```python
# auth.py — Middleware de autorização

from enum import Enum
from functools import wraps

class Role(str, Enum):
    ADMIN = "admin"
    OPERADOR = "operador"
    ANALISTA = "analista"
    ADVOGADO = "advogado"

# Permissões por recurso
PERMISSIONS = {
    "dashboard_home":      [Role.ADMIN, Role.OPERADOR],
    "portfolio_full":      [Role.ADMIN, Role.OPERADOR],
    "portfolio_readonly":  [Role.ADMIN, Role.OPERADOR, Role.ANALISTA],
    "financeiro":          [Role.ADMIN],
    "leads_gestao":        [Role.ADMIN, Role.OPERADOR],
    "outbound_disparo":    [Role.ADMIN, Role.OPERADOR],
    "templates_gestao":    [Role.ADMIN],
    "usuarios_gestao":     [Role.ADMIN],
    "cessao_registrar":    [Role.ADMIN, Role.OPERADOR],
    "dados_sensiveis":     [Role.ADMIN],          # CPFs, valores
    "portal_advogado":     [Role.ADVOGADO],
    "comissoes_proprias":  [Role.ADVOGADO],
}

def require_role(*roles):
    """Decorator para proteger endpoints por role."""
    def decorator(func):
        @wraps(func)
        async def wrapper(request, *args, **kwargs):
            user = get_current_user(request)  # JWT do Cognito
            if user.role not in roles:
                raise HTTPException(403, "Acesso negado")
            return await func(request, *args, **kwargs)
        return wrapper
    return decorator

# Uso nos endpoints:
@app.get("/api/financeiro")
@require_role(Role.ADMIN)
async def get_financeiro():
    ...

@app.get("/api/portfolio")
@require_role(Role.ADMIN, Role.OPERADOR, Role.ANALISTA)
async def get_portfolio(user = Depends(get_current_user)):
    # Mascarar CPFs para role ANALISTA
    if user.role == Role.ANALISTA:
        return mascarar_dados_sensiveis(portfolio)
    return portfolio
```

**Dados sensíveis — mascaramento por role:**

| Dado | Admin | Operador | Analista | Advogado |
|------|-------|----------|----------|----------|
| CPF credor | Completo | Completo | \*\*\*.456.789-\*\* | N/A |
| Valor RPV | Completo | Completo | Completo | Só suas indicações |
| Valor cessão | Completo | Completo | Oculto | N/A |
| Margem/lucro | Completo | Oculto | Oculto | N/A |
| Dados bancários | Completo | Oculto | Oculto | N/A |
| Comissão advogado | Completo | Completo | Oculto | Só própria |

### 6.4 Gerenciamento de Templates Meta

Tela dedicada no dashboard (acesso: Admin) para gerenciar templates WhatsApp aprovados pela Meta.

**Funcionalidades:**

1. **Listar templates:** Puxa da Meta Business API todos os templates da WABA, mostrando nome, status (aprovado/rejeitado/pendente), categoria, idioma
2. **Criar template:** Formulário para submeter novo template à Meta para aprovação. Campos: nome, categoria (marketing/utility), corpo com variáveis {{1}}, {{2}}, botões (quick reply / CTA)
3. **Preview:** Visualização de como o template aparece no WhatsApp antes de submeter
4. **Métricas por template:** Taxa de entrega, taxa de leitura, taxa de resposta, conversões
5. **Histórico de uso:** Quando e para quem cada template foi disparado

**Integração com Meta Business API:**

```python
# templates_manager.py

META_API_BASE = "https://graph.facebook.com/v21.0"

async def listar_templates(waba_id: str) -> list:
    """Lista todos os templates da WABA."""
    response = await httpx.get(
        f"{META_API_BASE}/{waba_id}/message_templates",
        headers={"Authorization": f"Bearer {META_TOKEN}"},
        params={"limit": 100}
    )
    return response.json()["data"]

async def criar_template(waba_id: str, template: dict) -> dict:
    """Submete novo template para aprovação da Meta."""
    response = await httpx.post(
        f"{META_API_BASE}/{waba_id}/message_templates",
        headers={"Authorization": f"Bearer {META_TOKEN}"},
        json={
            "name": template["name"],
            "language": "pt_BR",
            "category": template["category"],  # MARKETING ou UTILITY
            "components": template["components"],
        }
    )
    return response.json()

async def deletar_template(waba_id: str, template_name: str) -> dict:
    """Remove template."""
    response = await httpx.delete(
        f"{META_API_BASE}/{waba_id}/message_templates",
        headers={"Authorization": f"Bearer {META_TOKEN}"},
        params={"name": template_name}
    )
    return response.json()
```

**Tela de templates (wireframe):**

```
┌─────────────────────────────────────────────────────────┐
│  TEMPLATES META       [+ Novo template]    [Sincronizar]│
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Nome              │ Categoria │ Status    │ Métricas   │
│────────────────────┼───────────┼───────────┼────────────│
│  rpv_antecipacao   │ Marketing │ ✅ Aprovado│ 45% resp. │
│  rpv_followup      │ Utility   │ ✅ Aprovado│ 32% resp. │
│  rpv_pagamento     │ Utility   │ ✅ Aprovado│ 78% resp. │
│  rpv_advogado      │ Marketing │ ⏳ Pendente│ —         │
│  rpv_natal_2026    │ Marketing │ ❌ Rejeitado│ —        │
│                                                         │
│  Click no template para editar, ver preview ou métricas │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Módulo 4 — Portal do Advogado

### 7.1 Funcionalidades

1. **Cadastro:** Nome, OAB, escritório, telefone, email
2. **Indicar RPV:** Informa número do processo → sistema busca no banco → gera proposta → advogado compartilha link wa.me personalizado com o cliente
3. **Meus honorários:** Antecipar honorários próprios (mesmo fluxo)
4. **Acompanhar:** Status de cada indicação, comissão acumulada
5. **Dashboard:** Total indicado, conversões, comissões pagas/pendentes

### 7.2 Stack

Mesmo do dashboard: React + Amplify. Auth via Cognito com role `advogado` — acesso restrito ao portal.

---

## 8. Modelo de Dados Completo

```sql
-- LEADS E CONVERSAS
CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT,
    telefone TEXT NOT NULL,
    cpf_cnpj TEXT,
    tipo TEXT CHECK (tipo IN ('credor_pf','credor_pj','advogado')),
    origem TEXT,  -- inbound, outbound, parceiro
    advogado_id UUID REFERENCES advogados(id),
    numero_processo TEXT,
    valor_rpv DECIMAL(12,2),
    score INTEGER,
    status TEXT DEFAULT 'novo',
    -- novo → qualificado → proposta → aceito → cessao → finalizado
    proposta_valor DECIMAL(12,2),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE sessoes_whatsapp (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telefone TEXT NOT NULL UNIQUE,
    historico_mensagens JSONB DEFAULT '[]',
    contexto JSONB DEFAULT '{}',  -- rpv_data, etapa, etc
    ultima_interacao TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'ativo'  -- ativo, encerrado, handoff
);

CREATE TABLE mensagens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sessao_id UUID REFERENCES sessoes_whatsapp(id),
    direcao TEXT CHECK (direcao IN ('inbound','outbound')),
    tipo TEXT,  -- texto, imagem, audio, template
    conteudo TEXT,
    template_nome TEXT,  -- se outbound template
    created_at TIMESTAMPTZ DEFAULT now()
);

-- MOTOR DE DADOS
CREATE TABLE pagamentos_rpv (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_rpv TEXT,
    ano_rpv INTEGER,
    numero_processo TEXT,
    credor TEXT,
    cpf_cnpj TEXT,
    valor DECIMAL(12,2),
    data_pagamento DATE,
    status TEXT,  -- aceito, rejeitado
    lote_origem TEXT,
    municipio TEXT DEFAULT 'São Paulo',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(numero_rpv, ano_rpv, cpf_cnpj)
);

CREATE TABLE expedicao_rpv (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_processo TEXT UNIQUE,
    data_expedicao DATE,
    prazo_dias INTEGER,
    partes JSONB,
    score INTEGER,
    score_detalhes JSONB,
    fonte TEXT DEFAULT 'esaj',
    consultado_em TIMESTAMPTZ DEFAULT now()
);

-- OPERAÇÃO
CREATE TABLE cessoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES leads(id),
    numero_rpv TEXT,
    numero_processo TEXT,
    credor_original TEXT,
    cpf_cnpj_credor TEXT,
    valor_face DECIMAL(12,2),
    valor_adiantamento DECIMAL(12,2),
    data_cessao DATE,
    data_registro_judicial DATE,
    status TEXT DEFAULT 'ativa',
    -- ativa → paga_prefeitura → complemento_devido → finalizada
    data_recebimento_prefeitura DATE,
    valor_recebido_prefeitura DECIMAL(12,2),
    prazo_real_dias INTEGER,
    complemento_devido DECIMAL(12,2),
    complemento_pago DECIMAL(12,2),
    data_complemento DATE,
    lucro_realizado DECIMAL(12,2),
    margem_realizada DECIMAL(5,4),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- PARCEIROS
CREATE TABLE advogados (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    oab TEXT NOT NULL,
    escritorio TEXT,
    telefone TEXT NOT NULL,
    email TEXT,
    comissao_pct DECIMAL(5,4) DEFAULT 0.03,
    status TEXT DEFAULT 'ativo',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE comissoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    advogado_id UUID REFERENCES advogados(id),
    cessao_id UUID REFERENCES cessoes(id),
    valor DECIMAL(12,2),
    status TEXT DEFAULT 'pendente',
    data_pagamento DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- OUTBOUND
CREATE TABLE campanhas_outbound (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT,
    template_nome TEXT,  -- nome do template Meta
    filtro_valor_min DECIMAL(12,2),
    filtro_atraso_min INTEGER,
    status TEXT DEFAULT 'rascunho',
    -- rascunho → agendada → em_andamento → concluida
    disparos_total INTEGER DEFAULT 0,
    respostas_total INTEGER DEFAULT 0,
    conversoes_total INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE disparos_outbound (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campanha_id UUID REFERENCES campanhas_outbound(id),
    telefone TEXT,
    numero_processo TEXT,
    template_params JSONB,
    status TEXT DEFAULT 'pendente',
    -- pendente → enviado → respondido → convertido → opt_out
    enviado_em TIMESTAMPTZ,
    respondido_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- MONITORAMENTO
CREATE TABLE monitoramento_crawler (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo TEXT,  -- crawler_prefeitura, esaj_batch
    status TEXT,  -- sucesso, erro
    registros_processados INTEGER,
    detalhes JSONB,
    executado_em TIMESTAMPTZ DEFAULT now()
);

-- VIEWS
CREATE VIEW v_rpvs_elegiveis_outbound AS
SELECT 
    e.numero_processo,
    p.credor,
    p.valor,
    e.data_expedicao,
    CURRENT_DATE - e.data_expedicao AS dias_atraso,
    e.score
FROM expedicao_rpv e
JOIN pagamentos_rpv p ON e.numero_processo = p.numero_processo
WHERE p.status = 'aceito'
  AND p.valor >= 15000
  AND (CURRENT_DATE - e.data_expedicao) > 60
  AND e.score >= 40
  AND NOT EXISTS (
      SELECT 1 FROM cessoes c WHERE c.numero_processo = e.numero_processo
  )
  AND NOT EXISTS (
      SELECT 1 FROM disparos_outbound d 
      WHERE d.numero_processo = e.numero_processo 
      AND d.created_at > CURRENT_DATE - INTERVAL '30 days'
  );

CREATE VIEW v_portfolio AS
SELECT 
    c.*,
    e.data_expedicao,
    COALESCE(c.prazo_real_dias, CURRENT_DATE - e.data_expedicao) AS dias_corridos,
    CASE 
        WHEN c.status = 'finalizada' THEN c.margem_realizada
        ELSE calcular_margem_projetada(CURRENT_DATE - e.data_expedicao)
    END AS margem_atual
FROM cessoes c
LEFT JOIN expedicao_rpv e ON c.numero_processo = e.numero_processo;

CREATE VIEW v_financeiro AS
SELECT
    SUM(valor_face) AS carteira_face,
    SUM(valor_adiantamento) AS total_adiantado,
    SUM(CASE WHEN status != 'ativa' THEN valor_recebido_prefeitura ELSE 0 END) AS total_recebido,
    SUM(COALESCE(complemento_pago, 0)) AS total_complementos,
    SUM(COALESCE(lucro_realizado, 0)) AS lucro_total,
    AVG(CASE WHEN status = 'finalizada' THEN margem_realizada END) AS margem_media,
    COUNT(*) FILTER (WHERE status = 'ativa') AS rpvs_ativas,
    COUNT(*) FILTER (WHERE status = 'finalizada') AS rpvs_finalizadas
FROM cessoes;

-- USERS E ROLES (Cognito gerencia auth, esta tabela guarda perfil)
CREATE TABLE usuarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub TEXT UNIQUE NOT NULL,  -- ID do Cognito
    nome TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin','operador','analista','advogado')),
    telefone TEXT,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- TEMPLATES META (espelho local dos templates da WABA)
CREATE TABLE templates_meta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meta_template_id TEXT,          -- ID retornado pela Meta API
    nome TEXT NOT NULL,             -- ex: rpv_antecipacao_inicial
    categoria TEXT NOT NULL,        -- MARKETING, UTILITY
    status TEXT DEFAULT 'pendente', -- pendente, aprovado, rejeitado
    corpo TEXT NOT NULL,            -- Texto com {{1}}, {{2}}
    botoes JSONB,                   -- [{type: "QUICK_REPLY", text: "..."}]
    idioma TEXT DEFAULT 'pt_BR',
    disparos_total INTEGER DEFAULT 0,
    respostas_total INTEGER DEFAULT 0,
    taxa_resposta DECIMAL(5,4),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- AUDIT LOG (rastreabilidade de ações sensíveis)
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID REFERENCES usuarios(id),
    acao TEXT NOT NULL,             -- ex: cessao_registrada, lead_excluido
    recurso TEXT NOT NULL,          -- ex: cessoes, leads
    recurso_id UUID,
    detalhes JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 9. Scheduling e Jobs (EventBridge + Lambda + ECS Task + APScheduler)

### 9.1 Arquitetura de scheduling

Scheduling é híbrido: **EventBridge** dispara jobs batch (Lambda e ECS Task), **APScheduler** roda dentro do ECS Fargate do bot para alertas internos em tempo real.

```
EventBridge (jobs batch — executa e morre):
├── cron 6h  → Lambda: crawler_prefeitura
├── cron 7h  → ECS Task: esaj_batch (Playwright)
├── cron 9h  → Lambda: outbound_scheduler
├── cron 10h → Lambda: followup_leads
└── cron 18h → Lambda: relatorio_diario

APScheduler dentro do ECS Fargate (sempre rodando):
├── A cada 1h → verificar_pagamentos (cruza novos PDFs com carteira)
└── Sob demanda → alertar_operador (quando RPV em carteira é paga)
```

```python
# scheduler.py (dentro do ECS Fargate — apenas alertas internos)

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

scheduler = AsyncIOScheduler()

# Apenas jobs que precisam rodar DENTRO do bot (always-on)
# Jobs batch pesados rodam via EventBridge → Lambda/ECS Task

scheduler.add_job(
    job_verificar_pagamentos,
    CronTrigger(hour="*/1"),             # A cada hora
    id="verificar_pagamentos",
    name="Cruza novos pagamentos com carteira"
)

# Os jobs abaixo rodam via EventBridge → Lambda (separados):
# - crawler_prefeitura    → Lambda, cron 6h
# - esaj_batch            → ECS Task, cron 7h  
# - outbound_scheduler    → Lambda, cron 9h seg-sex
# - followup_leads        → Lambda, cron 10h seg-sex
# - relatorio_diario      → Lambda, cron 18h seg-sex
```

### 9.2 Jobs detalhados

```python
# jobs.py

async def job_crawler_prefeitura():
    """Diário 6h: Verifica novos lotes de PDFs na Prefeitura."""
    novos_pdfs = await descobrir_novos_pdfs()
    for url in novos_pdfs:
        pdf = await baixar_pdf(url)
        registros = parsear_pdf(pdf)
        await salvar_banco(registros)
        # Verifica se algum RPV em carteira foi pago
        await verificar_carteira(registros)
    await log_execucao("crawler_prefeitura", len(novos_pdfs))


async def job_enriquecimento_esaj():
    """Diário 7h: Enriquece registros novos com dados do TJSP."""
    pendentes = await buscar_rpvs_sem_data_expedicao()
    for rpv in pendentes:
        resultado = await consultar_tjsp(rpv["numero_processo"])
        if resultado["data_expedicao"]:
            await atualizar_expedicao(rpv, resultado)
            await calcular_e_salvar_score(rpv, resultado)
        await asyncio.sleep(4)  # Rate limiting ESAJ
    await log_execucao("enriquecimento_esaj", len(pendentes))


async def job_outbound_scheduler():
    """Seg-Sex 9h: Dispara templates Meta para RPVs elegíveis."""
    elegiveis = await buscar_rpvs_elegiveis_outbound()
    disparados = 0
    for rpv in elegiveis[:50]:  # Máximo 50/dia
        await enviar_template_meta(
            telefone=rpv["telefone"],  # Se disponível
            template="rpv_antecipacao_inicial",
            params={
                "nome": rpv["credor"],
                "valor": formatar_moeda(rpv["valor"]),
            }
        )
        await registrar_disparo(rpv)
        disparados += 1
    await log_execucao("outbound_scheduler", disparados)


async def job_followup():
    """Seg-Sex 10h: Follow-up em leads sem resposta há 7 dias."""
    leads = await buscar_leads_sem_resposta(dias=7)
    for lead in leads:
        await enviar_template_meta(
            telefone=lead["telefone"],
            template="rpv_followup",
            params={
                "nome": lead["nome"],
                "valor": formatar_moeda(lead["valor_rpv"]),
                "dias": str(lead["dias_atraso"]),
                "adiantamento": formatar_moeda(lead["valor_rpv"] * 0.5),
            }
        )
    await log_execucao("followup", len(leads))


async def job_verificar_pagamentos():
    """Diário 12h: Cruza novos pagamentos com carteira."""
    novos_pagamentos = await buscar_pagamentos_recentes()
    for pgto in novos_pagamentos:
        cessao = await buscar_cessao_por_rpv(pgto["numero_rpv"])
        if cessao:
            # RPV em carteira foi paga!
            prazo_real = (pgto["data_pagamento"] - cessao["data_expedicao"]).days
            complemento = calcular_complemento(cessao["valor_face"], prazo_real)
            
            await atualizar_cessao(cessao["id"], {
                "status": "paga_prefeitura",
                "data_recebimento_prefeitura": pgto["data_pagamento"],
                "valor_recebido_prefeitura": pgto["valor"],
                "prazo_real_dias": prazo_real,
                "complemento_devido": complemento,
            })
            
            # Alerta operador via WhatsApp
            await alertar_operador(
                f"RPV {pgto['numero_rpv']} PAGA! "
                f"Valor: R$ {pgto['valor']:.2f} | "
                f"Prazo: {prazo_real} dias | "
                f"Complemento: R$ {complemento:.2f}"
            )
    await log_execucao("verificar_pagamentos", len(novos_pagamentos))


async def job_relatorio_diario():
    """Seg-Sex 18h: Resumo diário para operadores."""
    metricas = await compilar_metricas_diarias()
    msg = (
        f"📊 *Resumo do dia*\n"
        f"Leads novos: {metricas['leads_novos']}\n"
        f"Propostas enviadas: {metricas['propostas']}\n"
        f"Cessões fechadas: {metricas['cessoes']}\n"
        f"RPVs pagas hoje: {metricas['pagamentos']}\n"
        f"Capital disponível: R$ {metricas['capital_livre']:,.2f}\n"
        f"Lucro acumulado: R$ {metricas['lucro_total']:,.2f}"
    )
    await alertar_operador(msg)


async def alertar_operador(mensagem: str):
    """Envia mensagem WhatsApp para os operadores."""
    for operador in OPERADORES:
        await enviar_whatsapp(operador["telefone"], mensagem)
```

### 9.3 Integração com FastAPI

```python
# main.py

from fastapi import FastAPI
from contextlib import asynccontextmanager
from scheduler import scheduler

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: inicia scheduler
    scheduler.start()
    yield
    # Shutdown: para scheduler
    scheduler.shutdown()

app = FastAPI(lifespan=lifespan)

@app.get("/webhook")
async def verify_webhook(...):
    ...

@app.post("/webhook")
async def receive_message(...):
    ...

@app.get("/health")
async def health():
    """Health check — inclui status dos jobs."""
    jobs = scheduler.get_jobs()
    return {
        "status": "ok",
        "jobs": [
            {
                "id": j.id,
                "name": j.name,
                "next_run": str(j.next_run_time)
            }
            for j in jobs
        ]
    }
```

### 9.4 Webhook Meta → Bot

```
Meta Cloud API → POST /webhook (FastAPI)
                    ↓
              Identifica tipo de mensagem
                    ↓
              ┌─────┴─────┐
              ▼           ▼
         [Resposta a    [Mensagem
          template]      orgânica]
              ↓           ↓
         Carrega        Carrega
         contexto       sessão
         do disparo     existente
              ↓           ↓
              └─────┬─────┘
                    ▼
            Claude Agent SDK
            + Skills + Tools
                    ↓
            Resposta via
            Meta Cloud API
```

---

## 10. Requisitos Não-Funcionais

| Requisito | Especificação |
|-----------|---------------|
| Disponibilidade webhook | 99.9% (Meta desativa webhook se falhar muito) |
| Tempo de resposta bot | <5s (lê banco local, não consulta TJSP em tempo real) |
| Rate limiting ESAJ | 1 req/4s, máx 200/dia (batch only, ECS Task) |
| Rate limiting Meta | Respeitar tier do WABA (início: 1k msgs/dia, escala gradual) |
| Segurança | LGPD compliance, CPFs encriptados at rest (RDS encryption), webhook validado por assinatura Meta |
| RBAC | 4 roles (admin, operador, analista, advogado) via Cognito + JWT. Mascaramento de dados sensíveis por role |
| Audit trail | Todas as ações sensíveis (cessões, acessos a CPF, exclusões) logadas em audit_log |
| Backup | RDS automated backup diário + retenção 7 dias |
| Logs | Todas as mensagens WhatsApp armazenadas, retenção 2 anos. CloudWatch para infra |
| Monitoramento | CloudWatch alarms + /health endpoint + alertas WhatsApp para operadores |
| LLM fallback | OpenRouter com fallback automático entre providers. Se provider primário falhar, roteia para secundário sem interrupção |
| Custo LLM | Monitoramento de custo por tarefa via dashboard OpenRouter. Alertas se custo diário exceder threshold |

---

## 11. Backlog Priorizado

### Sprint 1 (Semana 1-2): Infra + Motor de Dados

| # | Story | P |
|---|-------|---|
| 1 | Setup AWS: RDS, ECS, ECR, EventBridge, Cognito, Secrets Manager | P0 |
| 2 | Crawler baixa e parseia PDFs da Prefeitura automaticamente (Lambda) | P0 |
| 3 | Enriquecimento batch via ESAJ (ECS Task com Playwright) | P0 |
| 4 | Scoring de risco por RPV | P1 |
| 5 | View de RPVs elegíveis para outbound | P1 |

### Sprint 2 (Semana 3-4): Bot WhatsApp MVP

| # | Story | P |
|---|-------|---|
| 6 | Setup Meta Cloud API + webhook FastAPI (ECS Fargate) | P0 |
| 7 | Integração OpenRouter (multi-provider LLM com fallback) | P0 |
| 8 | Agent Skills: rpv-acolhimento, rpv-qualificacao, rpv-proposta, rpv-objecoes, rpv-advogado | P0 |
| 9 | Tools Python: buscar_rpv, calcular_proposta, registrar_lead, verificar_cessao | P0 |
| 10 | Fluxo inbound completo (skills guiam a conversa) | P0 |
| 11 | Gestão de sessão/contexto no PostgreSQL | P0 |
| 12 | Suporte a foto (Claude Vision via OpenRouter extrai número processo) | P1 |

### Sprint 3 (Semana 5-6): Outbound + Dashboard + RBAC

| # | Story | P |
|---|-------|---|
| 13 | Templates Meta: submissão e aprovação dos 4 templates iniciais | P0 |
| 14 | Tela de gerenciamento de templates (criar, listar, preview, métricas) | P1 |
| 15 | Workflow outbound (Lambda): seleciona RPVs → dispara templates → registra | P0 |
| 16 | RBAC com Cognito: roles admin, operador, analista, advogado | P0 |
| 17 | Dashboard Home (métricas + alertas) com permissões por role | P1 |
| 18 | Dashboard Portfólio (tabela de RPVs em carteira) | P1 |
| 19 | Alerta automático quando Prefeitura paga RPV em carteira | P0 |

### Sprint 4 (Semana 7-8): Portal Advogado + Refinamentos

| # | Story | P |
|---|-------|---|
| 20 | Portal advogado: cadastro + indicar RPV + acompanhar | P1 |
| 21 | Dashboard Financeiro (fluxo caixa, ROI) — acesso Admin only | P1 |
| 22 | Dashboard Leads/CRM (pipeline Kanban) | P2 |
| 23 | Dashboard Outbound (métricas de campanha por template) | P2 |
| 24 | Follow-up automático para leads sem resposta (Lambda) | P2 |
| 25 | Audit log de ações sensíveis | P2 |
| 26 | Mascaramento de CPF por role (analista vê mascarado) | P2 |
| 27 | Suporte a áudio (transcrição via OpenRouter/Whisper) | P2 |

---

## 12. Estrutura de Diretório do Projeto

```
rpv-capital/
├── README.md
├── requirements.txt
├── docker-compose.yml
│
├── .skills/                        # Agent Skills (agentskills.io)
│   ├── rpv-acolhimento/
│   │   └── SKILL.md               # Recepção, identificação credor/advogado
│   ├── rpv-qualificacao/
│   │   └── SKILL.md               # Coleta processo, busca no banco, valida
│   ├── rpv-proposta/
│   │   ├── SKILL.md               # Apresenta proposta escalonada
│   │   └── references/
│   │       └── tabela_escalonada.md
│   ├── rpv-objecoes/
│   │   ├── SKILL.md               # Trata dúvidas e objeções
│   │   └── references/
│   │       ├── faq.md             # Perguntas frequentes
│   │       └── legal.md           # Base legal da cessão
│   ├── rpv-advogado/
│   │   └── SKILL.md               # Programa de parceria, comissão
│   └── rpv-outbound/
│       ├── SKILL.md               # Contexto quando credor vem de outbound
│       └── references/
│           └── templates.md       # Templates Meta aprovados
│
├── bot/                            # ECS Fargate (always-on)
│   ├── Dockerfile                  # Container para ECS
│   ├── main.py                     # FastAPI server (webhook Meta)
│   ├── agent.py                    # Claude Agent SDK + Skills loader
│   ├── scheduler.py                # APScheduler (apenas alertas internos)
│   ├── tools/
│   │   ├── __init__.py
│   │   ├── buscar_rpv.py           # Consulta RDS
│   │   ├── calcular_proposta.py    # Lógica escalonada
│   │   ├── registrar_lead.py       # Salva lead
│   │   ├── verificar_cessao.py     # Checa duplicidade
│   │   ├── agendar_humano.py       # Handoff para operador
│   │   ├── enviar_template.py      # Disparo outbound Meta
│   │   └── buscar_faq.py           # Knowledge base
│   ├── whatsapp/
│   │   ├── meta_api.py             # Meta Cloud API client
│   │   ├── templates.py            # Template management
│   │   └── media.py                # Processar imagens/áudio
│   ├── sessions/
│   │   └── manager.py              # Gestão de sessões PostgreSQL
│   └── skills_loader.py            # Carrega .skills/ para o SDK
│
├── lambdas/                        # AWS Lambda functions
│   ├── crawler_prefeitura/
│   │   ├── handler.py              # EventBridge cron 6h → baixa e parseia PDFs
│   │   └── requirements.txt
│   ├── outbound_scheduler/
│   │   ├── handler.py              # EventBridge cron 9h → dispara templates
│   │   └── requirements.txt
│   ├── followup_leads/
│   │   ├── handler.py              # EventBridge cron 10h → follow-up
│   │   └── requirements.txt
│   ├── relatorio_diario/
│   │   ├── handler.py              # EventBridge cron 18h → resumo WhatsApp
│   │   └── requirements.txt
│   └── shared/
│       ├── db_client.py      # Client PostgreSQL compartilhado
│       ├── meta_api.py             # Client Meta compartilhado
│       └── alerts.py               # Envio alertas WhatsApp
│
├── esaj_task/                      # ECS Task (batch sob demanda)
│   ├── Dockerfile                  # Container com Playwright + Chromium
│   ├── main.py                     # Entry point: enriquece RPVs via TJSP
│   ├── consulta.py                 # Playwright automation ESAJ
│   └── requirements.txt
│
├── motor/                          # Lógica compartilhada (import por bot, lambdas, task)
│   ├── crawler/
│   │   ├── prefeitura_sp.py        # Crawler PDFs
│   │   └── parser_pdf.py           # Parser pdfplumber
│   ├── scoring/
│   │   └── risk_score.py           # Scoring de risco
│   └── models/
│       └── proposta.py             # Cálculo da proposta escalonada
│
├── dashboard/                      # Amplify (React estático)
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Home.tsx
│   │   │   ├── Portfolio.tsx
│   │   │   ├── Financeiro.tsx
│   │   │   ├── Leads.tsx
│   │   │   └── Outbound.tsx
│   │   ├── components/
│   │   └── lib/
│   │       └── db.ts
│   └── package.json
│
├── portal-advogado/                # Amplify (React estático)
│   └── ...
│
├── database/
│   └── migrations/
│       └── 001_initial_schema.sql
│
└── infra/
    ├── template.yaml               # SAM / CloudFormation (Lambdas + EventBridge)
    ├── taskdef.json                 # ECS Task definition (ESAJ)
    ├── service.json                 # ECS Service definition (Bot)
    └── amplify.yml                  # Amplify build config
```

**Organização:**
- `bot/` → deploy para ECS Fargate (always-on)
- `lambdas/` → deploy para AWS Lambda via SAM/CloudFormation
- `esaj_task/` → deploy para ECS Task (container com Playwright)
- `motor/` → código compartilhado (importado por todos)
- `dashboard/` e `portal-advogado/` → deploy para Amplify
- `infra/` → IaC (Infrastructure as Code)

---

## 13. Cronograma

| Fase | Semanas | Entregas |
|------|---------|----------|
| Sprint 1: Infra + Motor de Dados | 1-2 | AWS setup + Crawler + ESAJ batch + RDS populado |
| Sprint 2: Bot WhatsApp MVP | 3-4 | Bot inbound com OpenRouter + Skills + Tools |
| Sprint 3: Outbound + Dashboard + RBAC | 5-6 | Templates Meta + outbound ativo + dashboard com roles |
| Sprint 4: Portal Advogado + Refinamentos | 7-8 | Portal parceiro + financeiro + audit log |
| **Total MVP** | **8 semanas** | **Plataforma operacional completa** |

Primeiras cessões podem acontecer na Sprint 3 (semana 5-6), quando o outbound estiver disparando e os primeiros credores responderem.

---

## 14. Práticas de Desenvolvimento — SuperClaude Framework

O desenvolvimento da plataforma RPV Capital será feito usando **Claude Code** com o **SuperClaude Framework v4.2** para acelerar e estruturar o ciclo de desenvolvimento.

### 14.1 O que é o SuperClaude

Framework de meta-programação (21k+ stars) que transforma o Claude Code num ambiente de desenvolvimento estruturado com 30 comandos, 16 agentes especializados, 7 modos comportamentais e 8 integrações MCP. Instalação via `pipx install superclaude && superclaude install`.

### 14.2 MCP Servers para instalar

8 MCP servers disponíveis. Para o RPV Capital, instalar **6 dos 8** (pular chrome-devtools e magic que são menos relevantes para backend Python):

```bash
superclaude mcp --servers sequential-thinking context7 tavily playwright serena morphllm
```

| MCP Server | Para quê | Uso no RPV Capital |
|-----------|---------|-------------------|
| **Sequential Thinking** | Raciocínio multi-step, análise complexa. 30-50% menos tokens | Design da arquitetura de agentes, modelagem de dados, debugging de fluxos complexos |
| **Context7** | Documentação oficial de libraries em tempo real (evita alucinações) | Consultar docs do FastAPI, Playwright, Meta Cloud API, APScheduler, OpenRouter SDK — sempre versão atual |
| **Tavily** | Pesquisa web para deep research | Pesquisar atualizações na Meta Business API, mudanças regulatórias (EC 136), novos endpoints do TJSP |
| **Playwright** | Automação de browser e testes E2E | Desenvolver e testar o scraper ESAJ, testar o dashboard, testes de integração |
| **Serena** | Entendimento semântico de código e memória de projeto (2-3x mais rápido) | Navegar o codebase RPV Capital, entender dependências entre módulos, manter contexto entre sessões |
| **Morphllm (Fast Apply)** | Transformações de código context-aware | Refatorações rápidas, aplicar padrões de código repetitivo nos tools e lambdas |

**Não instalar (por agora):**
- `chrome-devtools` — útil para frontend, mas o dashboard é fase posterior
- `magic` — geração de UI components, avaliar quando entrar na Sprint 3

### 14.3 Comandos SuperClaude por Sprint

**Sprint 1 — Infra + Motor de Dados:**

```bash
# Projetar arquitetura AWS
/sc:design "AWS infrastructure for RPV Capital: ECS Fargate, Lambda, EventBridge, RDS" --architect

# Implementar crawler
/sc:implement "PDF crawler for São Paulo RPV payments using pdfplumber" --backend

# Implementar scraper ESAJ
/sc:implement "Playwright-based TJSP ESAJ scraper with rate limiting" --backend

# Testes do motor
/sc:test "crawler and ESAJ scraper integration tests" --coverage

# Analisar qualidade do parser
/sc:analyze "PDF parsing accuracy across different lot formats"
```

**Sprint 2 — Bot WhatsApp:**

```bash
# Design do sistema de agentes
/sc:design "WhatsApp bot with OpenRouter multi-provider and Agent Skills" --architect

# Implementar webhook FastAPI
/sc:implement "Meta Cloud API webhook handler with signature validation" --backend

# Implementar tools do agente
/sc:implement "Agent tools: buscar_rpv, calcular_proposta, registrar_lead" --backend

# Revisão de segurança
/sc:analyze "security review of webhook handler and data handling" --security

# Testar fluxo conversacional
/sc:test "WhatsApp bot conversation flows end-to-end" --e2e
```

**Sprint 3 — Outbound + Dashboard:**

```bash
# Implementar Lambdas de outbound
/sc:implement "EventBridge Lambda for outbound RPV template dispatch" --backend

# Design do dashboard
/sc:design "React dashboard with RBAC for RPV portfolio management" --frontend

# Implementar RBAC
/sc:implement "Cognito JWT authorization middleware with 4 roles" --security

# Testes de segurança
/sc:analyze "RBAC permission matrix verification" --security
```

**Sprint 4 — Portal + Polish:**

```bash
# Portal do advogado
/sc:implement "Lawyer partner portal with commission tracking" --frontend

# Documentação
/sc:document "API documentation for all endpoints" 

# Retrospectiva
/sc:reflect "Sprint retrospective - what worked, what didn't"
```

### 14.4 Agentes SuperClaude relevantes

Dos 16 agentes, os mais úteis para o RPV Capital:

| Agente | Ativa com | Uso no projeto |
|--------|----------|----------------|
| **system-architect** | `/sc:design --architect` | Design da infra AWS, separação ECS/Lambda/Task, modelo de dados |
| **backend-developer** | `/sc:implement --backend` | Crawler, scraper ESAJ, tools do agente, webhook FastAPI, Lambdas |
| **security-engineer** | `/sc:analyze --security` | Validação de webhook Meta, RBAC, encriptação de CPFs, LGPD compliance |
| **frontend-architect** | `/sc:design --frontend` | Dashboard React, Portal do advogado |
| **testing-specialist** | `/sc:test --coverage` | Testes do parser PDF, testes do bot, testes de integração ESAJ |
| **performance-engineer** | `/sc:analyze --performance` | Otimização do scraper, rate limiting, cold start das Lambdas |
| **deep-research** | `/sc:research` | Pesquisa sobre Meta Business API, regulação SCD, atualizações TJSP |
| **pm-agent** | `/sc:pm` | Tracking de tasks, gestão de backlog, relatórios de progresso |

### 14.5 Modos comportamentais úteis

| Modo | Quando usar |
|------|-------------|
| **Brainstorming** | Início de cada sprint — definir abordagem, explorar alternativas |
| **Orchestration** | Implementação complexa — coordena múltiplos MCPs automaticamente |
| **Token-Efficiency** | Sessões longas de coding — reduz 30-50% de contexto |
| **Task Management** | Acompanhar progresso dentro de cada sprint |
| **Deep Research** | Pesquisar APIs externas, regulação, concorrentes |

### 14.6 Arquivos de projeto para o SuperClaude

O SuperClaude lê arquivos específicos no início de cada sessão. Criar estes no repo RPV Capital:

| Arquivo | Propósito | Conteúdo |
|---------|----------|----------|
| **CLAUDE.md** | Instruções base para o Claude Code | Stack do projeto (Python, FastAPI, AWS), convenções de código, regras de negócio RPV, modelo escalonado |
| **PLANNING.md** | Arquitetura e princípios | Arquitetura AWS (ECS/Lambda/RDS), separação de módulos, regras absolutas (ex: nunca consultar TJSP em tempo real no bot) |
| **TASK.md** | Backlog e prioridades | Cópia do backlog do PRD (27 stories), atualizar a cada sprint |
| **KNOWLEDGE.md** | Insights e aprendizados | Descoberta do truncamento CNJ (19→20 dígitos), rate limiting ESAJ (4s), padrão de PDFs da Prefeitura, modelo escalonado de precificação |

**Exemplo de CLAUDE.md para o RPV Capital:**

```markdown
# RPV Capital — Projeto

## Stack
- Python 3.11+ (backend, lambdas, agente)
- FastAPI (webhook Meta, API dashboard)
- Playwright (scraper ESAJ — apenas batch, nunca no bot)
- pdfplumber (parser PDFs da Prefeitura)
- OpenRouter SDK (multi-provider LLM via OpenAI-compatible)
- React + Tailwind + shadcn/ui (dashboard)
- AWS: ECS Fargate, Lambda, EventBridge, RDS PostgreSQL, Amplify, Cognito, ECR

## Regras absolutas
1. O bot NUNCA consulta TJSP em tempo real — sempre lê do RDS
2. Rate limiting ESAJ: 1 req a cada 4 segundos, máx 200/dia
3. CPFs devem ser encriptados at rest no RDS
4. Toda ação sensível precisa de entrada no audit_log
5. 4 roles RBAC: admin, operador, analista, advogado
6. Número do processo nos PDFs tem 19 dígitos — adicionar "3" para obter formato CNJ (20 dígitos)

## Convenções
- Tipo de dados monetários: DECIMAL(12,2)
- Datas: sempre TIMESTAMPTZ
- IDs: UUID (gen_random_uuid())
- Código em português para variáveis de negócio, inglês para infraestrutura
- Testes obrigatórios para todo tool do agente
```

### 14.7 Workflow recomendado por sessão

```
1. Abrir Claude Code no diretório rpv-capital/
2. SuperClaude carrega CLAUDE.md, PLANNING.md, TASK.md, KNOWLEDGE.md
3. Verificar task atual: /sc:pm "status"
4. Selecionar próxima task: /sc:task "next"
5. Implementar com agente apropriado: /sc:implement "..." --backend
6. Testar: /sc:test "..." --coverage
7. Revisar segurança se necessário: /sc:analyze --security
8. Salvar sessão: /sc:save "sprint1-crawler"
9. Atualizar TASK.md e KNOWLEDGE.md com aprendizados
```

### 14.8 AIRIS MCP Gateway (alternativa simplificada)

Se configurar 6 MCPs individuais for complexo, o **AIRIS MCP Gateway** consolida tudo num único endpoint SSE com 50 tools de 7 servers:

```bash
# Instala gateway único em vez de 6 MCPs separados
# Inclui: context7, sequential-thinking, serena, tavily, fetch, memory
# https://github.com/agiletec-inc/airis-mcp-gateway
```

Avaliar na Sprint 1 se o gateway simplifica o setup ou se instalar individualmente dá mais controle.
