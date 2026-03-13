# RPV Capital — Plataforma de Antecipação de RPVs Municipais

## Stack Técnica

### Backend & Agente
- **Python 3.11+** — toda lógica de negócio
- **FastAPI** — webhook Meta Cloud API, API do dashboard
- **OpenRouter SDK** — multi-provider LLM (Claude, GPT, Mistral) via OpenAI-compatible API
- **Agent Skills** (agentskills.io) — conhecimento procedural do agente
- **Playwright** — scraper ESAJ (apenas batch, NUNCA no bot)
- **pdfplumber** — parser PDFs da Prefeitura
- **APScheduler** — alertas internos no bot

### Frontend
- **React 18+** — dashboard e portal advogado
- **Tailwind CSS** — styling
- **shadcn/ui** — componentes
- **Recharts** — gráficos

### Infraestrutura AWS
- **ECS Fargate** — bot WhatsApp (always-on, 0.25 vCPU, 512MB)
- **ECS Task** — scraper ESAJ (batch sob demanda)
- **Lambda** — crawler PDFs, outbound, follow-up, relatórios
- **EventBridge** — scheduling de todos os jobs batch
- **RDS PostgreSQL** — banco principal (db.t4g.micro/small)
- **Amplify** — deploy dashboard e portal (S3 + CloudFront)
- **Cognito** — autenticação e RBAC
- **ECR** — registry de containers
- **Secrets Manager** — credenciais (Meta, OpenRouter, RDS)
- **CloudWatch** — logs e monitoramento

---

## Regras Absolutas

### Arquitetura
1. **Bot NUNCA consulta TJSP em tempo real** — sempre lê do RDS (banco pré-enriquecido)
2. **Rate limiting ESAJ**: 1 request a cada 4 segundos, máximo 200/dia
3. **Separação clara**: ECS Fargate (always-on) vs Lambda (event-driven) vs ECS Task (batch pesado)

### Segurança & Compliance
4. **CPFs encriptados at rest** no RDS (pgcrypto ou KMS)
5. **Toda ação sensível** precisa de entrada no `audit_log`
6. **4 roles RBAC**: admin, operador, analista, advogado
7. **Validar assinatura** `X-Hub-Signature-256` em todo webhook Meta
8. **Mascaramento de CPF** para role analista: `***.456.789-**`

### Dados
9. **Número do processo nos PDFs tem 19 dígitos** — adicionar "3" ao final para formato CNJ (20 dígitos)
10. **Teto RPV São Paulo 2026**: R$ 31.667,41
11. **Tipos monetários**: sempre `DECIMAL(12,2)`
12. **Datas**: sempre `TIMESTAMPTZ`
13. **IDs**: sempre `UUID` com `gen_random_uuid()`

### Bot & Conversas
14. **Tom de voz**: caloroso, simples (nível ensino médio), sem jargão jurídico
15. **Nunca pedir muitas informações de uma vez** — uma pergunta por mensagem
16. **Handoff para humano** quando: RPV não encontrada, objeção persistente, pedido explícito

---

## Convenções de Código

### Nomenclatura
- **Variáveis de negócio**: português (`valor_rpv`, `data_expedicao`, `credor`)
- **Infraestrutura**: inglês (`handler`, `scheduler`, `client`)
- **Arquivos**: snake_case (`buscar_rpv.py`, `calcular_proposta.py`)
- **Classes**: PascalCase (`LeadManager`, `WhatsAppClient`)

### Estrutura de Projeto
```
rpv-capital/
├── .skills/          # Agent Skills (SKILL.md + references)
├── bot/              # ECS Fargate (FastAPI + Agent SDK)
├── lambdas/          # AWS Lambda functions
├── esaj_task/        # ECS Task (Playwright batch)
├── motor/            # Lógica compartilhada
├── dashboard/        # React (Amplify)
├── portal-advogado/  # React (Amplify)
├── database/         # Migrations SQL
└── infra/            # IaC (SAM/CloudFormation)
```

### Testes
- Cobertura mínima: 80% para tools do agente
- Mocks obrigatórios para: RDS, Meta API, OpenRouter
- Testes de integração para: fluxos conversacionais, scraper ESAJ

---

## Modelo de Dados Resumido

### Tabelas Principais
| Tabela | Propósito |
|--------|-----------|
| `leads` | Credores e advogados em prospecção |
| `sessoes_whatsapp` | Estado das conversas |
| `mensagens` | Histórico de todas as mensagens |
| `pagamentos_rpv` | RPVs parseadas dos PDFs da Prefeitura |
| `expedicao_rpv` | Dados enriquecidos do ESAJ (data expedição, partes) |
| `cessoes` | RPVs compradas, em carteira |
| `advogados` | Parceiros com comissão |
| `comissoes` | Comissões devidas/pagas |
| `campanhas_outbound` | Campanhas de disparo proativo |
| `disparos_outbound` | Registro de cada template enviado |
| `usuarios` | Perfis com roles (Cognito sync) |
| `templates_meta` | Espelho dos templates aprovados pela Meta |
| `audit_log` | Rastreabilidade de ações sensíveis |

### Views Úteis
- `v_rpvs_elegiveis_outbound` — RPVs prontas para abordagem proativa
- `v_portfolio` — Carteira atual com margem projetada
- `v_financeiro` — Métricas financeiras consolidadas

---

## Modelo Escalonado de Precificação

| Prazo Pagamento | Adiantamento | Complemento | Total Credor | Margem Operação |
|-----------------|--------------|-------------|--------------|-----------------|
| 0-60 dias       | 50%          | 40%         | 90%          | 10%             |
| 61-90 dias      | 50%          | 30%         | 80%          | 20%             |
| 91-120 dias     | 50%          | 20%         | 70%          | 30%             |
| 121-180 dias    | 50%          | 10%         | 60%          | 40%             |
| 180+ dias       | 50%          | 0%          | 50%          | 50%             |

---

## Integrações Externas

| Serviço | Uso | Rate Limits |
|---------|-----|-------------|
| **Meta Cloud API** | WhatsApp Business | Tier inicial: 1k msgs/dia |
| **OpenRouter** | LLM multi-provider | Varia por provider |
| **ESAJ TJSP** | Consulta processos | 1 req/4s, 200/dia |
| **Prefeitura SP** | PDFs de pagamento | Sem limite (público) |

---

## Comandos SuperClaude Úteis

```bash
# Design de arquitetura
/sc:design "componente" --architect

# Implementação backend
/sc:implement "feature" --backend

# Análise de segurança
/sc:analyze "componente" --security

# Testes
/sc:test "módulo" --coverage

# Pesquisa
/sc:research "tópico"

# Gestão de tarefas
/sc:pm "status"
```

---

## Links Úteis

- [Meta Cloud API Docs](https://developers.facebook.com/docs/whatsapp/cloud-api)
- [OpenRouter Docs](https://openrouter.ai/docs)
- [ESAJ TJSP](https://esaj.tjsp.jus.br/cpopg/open.do)
- [Agent Skills](https://agentskills.io)
- [FastAPI](https://fastapi.tiangolo.com)
