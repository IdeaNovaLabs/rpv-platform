# RPV Capital — Arquitetura e Planejamento

## Visão Arquitetural

### Princípio Central
O motor de dados roda em **batch** (diário) e alimenta o RDS com todas as RPVs conhecidas, já enriquecidas com dados do TJSP. O bot **nunca consulta o TJSP em tempo real** — ele lê do banco pronto. Isso elimina latência na conversa e dependência de disponibilidade do ESAJ.

### Diagrama de Alto Nível

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
│                    RDS PostgreSQL                               │
│                     RPVs enriquecidas                           │
│                             │                                   │
│            ┌────────────────┼────────────────┐                  │
│            ▼                ▼                ▼                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  BOT         │  │  DASHBOARD   │  │  PORTAL      │          │
│  │  WhatsApp    │  │  Operacional │  │  Advogado    │          │
│  │              │  │              │  │              │          │
│  │  ECS Fargate │  │  Amplify     │  │  Amplify     │          │
│  │  (always-on) │  │  (S3+CDN)    │  │  (S3+CDN)    │          │
│  │  FastAPI     │  │  React       │  │  React       │          │
│  │  OpenRouter  │  │  Recharts    │  │              │          │
│  │  Agent Skills│  │              │  │              │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
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

---

## Decisões Arquiteturais

### Por que ECS Fargate para o Bot (não Lambda)?

| Fator | Lambda | ECS Fargate |
|-------|--------|-------------|
| Cold start | 2-5s (mata UX do chat) | 0 (always-on) |
| Custo (50 msgs/dia) | ~$0 | ~$15-25/mês |
| WebSocket/long-running | Limitado | Suportado |
| APScheduler interno | Impossível | Funciona |

**Decisão**: ECS Fargate para o bot. O custo adicional compensa a experiência do usuário.

### Por que ECS Task para ESAJ (não Lambda)?

| Fator | Lambda | ECS Task |
|-------|--------|----------|
| Playwright + Chromium | ~1GB RAM, cold start 10s+ | Container pronto |
| Tempo execução | Max 15min | Ilimitado |
| Setup Docker | Complexo (layers) | Simples |

**Decisão**: ECS Task disparado por EventBridge. Roda ~30min/dia, custa ~$3-5/mês.

### Por que OpenRouter (não Anthropic direto)?

| Fator | Anthropic direto | OpenRouter |
|-------|------------------|------------|
| Fallback | Manual | Automático |
| Multi-provider | Impossível | Nativo |
| Custo | Fixo | Otimizável por tarefa |
| Monitoramento | DIY | Dashboard incluso |

**Decisão**: OpenRouter como camada de abstração. Permite usar modelos mais baratos para tarefas simples.

---

## Fluxo de Dados

### 1. Ingestão (Batch Diário)

```
06:00 - EventBridge dispara Lambda crawler_prefeitura
        ├── Acessa página da Prefeitura SP
        ├── Identifica novos PDFs de lotes
        ├── Baixa e parseia com pdfplumber
        ├── Normaliza números de processo (19→20 dígitos)
        └── Salva em pagamentos_rpv

07:00 - EventBridge dispara ECS Task esaj_batch
        ├── Busca RPVs sem data_expedicao
        ├── Consulta ESAJ (1 req/4s)
        ├── Extrai data expedição + partes
        ├── Calcula score de risco
        └── Salva em expedicao_rpv
```

### 2. Conversação (Tempo Real)

```
Credor manda WhatsApp
        │
        ▼
Meta Cloud API → POST /webhook (ECS Fargate)
        │
        ├── Valida assinatura X-Hub-Signature-256
        ├── Carrega sessão do PostgreSQL
        ├── Identifica skill necessária
        │
        ▼
OpenRouter (multi-provider)
        │
        ├── System prompt + Skill ativa
        ├── Tools disponíveis
        │
        ▼
Tool calls (se necessário)
        │
        ├── buscar_rpv_no_banco() → SELECT do RDS
        ├── calcular_proposta() → Lógica escalonada
        ├── registrar_lead() → INSERT no RDS
        │
        ▼
Resposta → Meta Cloud API → WhatsApp
```

### 3. Outbound (Batch Diário)

```
09:00 - EventBridge dispara Lambda outbound_scheduler
        ├── SELECT v_rpvs_elegiveis_outbound
        ├── Filtra: valor > 15k, atraso > 60 dias, sem cessão
        ├── Limita: 50/dia
        ├── Envia template Meta rpv_antecipacao_inicial
        └── Registra em disparos_outbound

Credor responde → fluxo inbound com contexto do disparo
```

---

## Segurança

### Camadas de Proteção

1. **Rede**: VPC com subnets privadas para RDS
2. **Autenticação**: Cognito + JWT para dashboard/portal
3. **Autorização**: RBAC com 4 roles
4. **Dados**: Encriptação at rest (RDS) e in transit (TLS)
5. **Auditoria**: audit_log para ações sensíveis
6. **Webhook**: Validação de assinatura Meta

### RBAC Matrix

| Recurso | Admin | Operador | Analista | Advogado |
|---------|-------|----------|----------|----------|
| Dashboard Home | ✅ | ✅ | ❌ | ❌ |
| Portfólio (completo) | ✅ | ✅ | ❌ | ❌ |
| Portfólio (read-only) | ✅ | ✅ | ✅ | ❌ |
| Financeiro | ✅ | ❌ | ❌ | ❌ |
| Leads/CRM | ✅ | ✅ | ❌ | ❌ |
| Outbound | ✅ | ✅ | ❌ | ❌ |
| Templates Meta | ✅ | ❌ | ❌ | ❌ |
| Usuários | ✅ | ❌ | ❌ | ❌ |
| Cessões (registrar) | ✅ | ✅ | ❌ | ❌ |
| CPFs completos | ✅ | ✅ | ❌ | ❌ |
| Portal Advogado | ❌ | ❌ | ❌ | ✅ |

---

## Failure Modes & Recovery

### Bot WhatsApp

| Falha | Detecção | Recovery |
|-------|----------|----------|
| OpenRouter timeout | Timeout 30s | Retry com backoff, fallback provider |
| RDS indisponível | Connection error | Resposta genérica, alerta operador |
| Webhook falha repetida | Meta desativa | Monitorar /health, alertar imediatamente |

### Motor de Dados

| Falha | Detecção | Recovery |
|-------|----------|----------|
| PDF formato novo | Parser exception | Alerta, fallback manual |
| ESAJ HTML mudou | Selector não encontrado | Alerta, pausa batch, ajuste manual |
| Rate limit excedido | HTTP 429 | Backoff exponencial, retry no dia seguinte |

### Dashboard

| Falha | Detecção | Recovery |
|-------|----------|----------|
| API down | Health check | Amplify retry, CloudWatch alarm |
| Cognito indisponível | Auth error | Cache de token, retry |

---

## Observabilidade

### Métricas de Negócio (CloudWatch Custom)

- `leads.novos` — Leads criados por dia
- `leads.conversao` — Taxa de conversão (proposta aceita / total)
- `outbound.disparos` — Templates enviados por dia
- `outbound.resposta` — Taxa de resposta
- `cessoes.valor` — Valor total de cessões no dia
- `bot.latencia` — Tempo médio de resposta

### Alertas Críticos

| Alerta | Threshold | Ação |
|--------|-----------|------|
| Bot latência > 5s | P95 | Investigar OpenRouter/RDS |
| Webhook error rate > 1% | 5 min | Verificar logs, Meta pode desativar |
| ESAJ success rate < 90% | 1h | Verificar se HTML mudou |
| Crawler falhou | 1 execução | Verificar página Prefeitura |

---

## Custos Estimados (MVP)

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

### Custos Variáveis

| Serviço | Custo |
|---------|-------|
| Meta WhatsApp (marketing template) | ~R$ 0,50/msg |
| Meta WhatsApp (utility template) | ~R$ 0,12/msg |
| Meta WhatsApp (service - janela 24h) | Gratuito |
| OpenRouter | Varia por modelo (~$0.001-0.01/1k tokens) |

---

## Decisões Tomadas

### Obtenção de Telefones para Outbound
**Decisão**: BigData Corp / Neoway (após validação do modelo)

**Estratégia de implementação**:
1. **MVP**: Inbound-first + parceiros advogados (sem custo de aquisição)
2. **Validação**: Confirmar unit economics com primeiras cessões
3. **Escala**: Integrar BigData Corp/Neoway para enriquecimento de base

**Fluxo de enriquecimento**:
```
RPV parseada do PDF (CPF + nome)
        ↓
Lambda enrich_telefone (batch diário)
        ↓
BigData Corp API (CPF → telefone)
        ↓
Salva em tabela leads_enriquecidos
        ↓
Elegível para outbound
```

**Considerações LGPD**:
- Base legal: Legítimo interesse (benefício claro ao credor)
- Requerer LIA (Legitimate Interest Assessment) antes de produção
- Implementar opt-out imediato no primeiro contato
- Registrar consentimento/recusa em audit_log

---

## Próximas Decisões Pendentes

1. **Ambiente de staging** — RDS separado ou schema isolado?
2. **CI/CD** — GitHub Actions ou AWS CodePipeline?
3. **Monitoramento** — CloudWatch suficiente ou adicionar Datadog/Grafana?
