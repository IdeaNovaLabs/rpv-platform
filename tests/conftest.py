"""
Pytest fixtures for RPV Capital tests.
"""
import asyncio
from typing import AsyncGenerator, Generator
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
from httpx import AsyncClient

# Database fixtures
@pytest.fixture(scope="session")
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_db() -> MagicMock:
    """Mock database connection."""
    db = MagicMock()
    db.execute = AsyncMock()
    db.fetch_one = AsyncMock()
    db.fetch_all = AsyncMock()
    return db


# OpenRouter fixtures
@pytest.fixture
def mock_openrouter() -> MagicMock:
    """Mock OpenRouter client."""
    client = MagicMock()
    client.chat.completions.create = AsyncMock(
        return_value=MagicMock(
            choices=[
                MagicMock(
                    message=MagicMock(
                        content="Olá! Sou da RPV Capital.",
                        tool_calls=None
                    )
                )
            ]
        )
    )
    return client


# Meta WhatsApp fixtures
@pytest.fixture
def mock_meta_api() -> MagicMock:
    """Mock Meta Cloud API client."""
    client = MagicMock()
    client.send_message = AsyncMock(return_value={"message_id": "test_123"})
    client.send_template = AsyncMock(return_value={"message_id": "test_456"})
    return client


# Sample data fixtures
@pytest.fixture
def sample_rpv() -> dict:
    """Sample RPV data for testing."""
    return {
        "numero_processo": "0019063-75.2025.8.26.0053",
        "numero_rpv": "12345/2025",
        "credor": "MARIA DA SILVA",
        "cpf_cnpj": "12345678901",
        "valor": 25000.00,
        "data_expedicao": "2024-10-15",
        "dias_desde_expedicao": 150,
        "status_pagamento": "pendente",
    }


@pytest.fixture
def sample_lead() -> dict:
    """Sample lead data for testing."""
    return {
        "nome": "Maria da Silva",
        "telefone": "5511999998888",
        "cpf_cnpj": "12345678901",
        "tipo": "credor_pf",
        "origem": "inbound",
        "numero_processo": "0019063-75.2025.8.26.0053",
        "valor_rpv": 25000.00,
    }


@pytest.fixture
def sample_sessao() -> dict:
    """Sample WhatsApp session data."""
    return {
        "telefone": "5511999998888",
        "historico_mensagens": [],
        "contexto": {
            "etapa": "acolhimento",
            "rpv_data": None,
        },
        "status": "ativo",
    }


# Webhook fixtures
@pytest.fixture
def webhook_message_payload() -> dict:
    """Sample Meta webhook message payload."""
    return {
        "object": "whatsapp_business_account",
        "entry": [
            {
                "id": "123456789",
                "changes": [
                    {
                        "value": {
                            "messaging_product": "whatsapp",
                            "metadata": {
                                "display_phone_number": "5511999997777",
                                "phone_number_id": "987654321"
                            },
                            "contacts": [
                                {
                                    "profile": {"name": "Maria"},
                                    "wa_id": "5511999998888"
                                }
                            ],
                            "messages": [
                                {
                                    "from": "5511999998888",
                                    "id": "wamid.test123",
                                    "timestamp": "1710340800",
                                    "type": "text",
                                    "text": {"body": "Olá, tenho um processo"}
                                }
                            ]
                        },
                        "field": "messages"
                    }
                ]
            }
        ]
    }


@pytest.fixture
def webhook_signature() -> str:
    """Sample webhook signature for testing."""
    return "sha256=abc123def456"
