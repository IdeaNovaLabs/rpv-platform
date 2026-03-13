"""
Integration tests for Meta webhook.
"""
import hashlib
import hmac
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock


class TestWebhookVerification:
    """Tests for webhook verification (GET /webhook)."""

    def test_verificacao_sucesso(self):
        """Should verify webhook with correct token."""
        from bot.main import app

        client = TestClient(app)

        with patch("bot.main.WEBHOOK_VERIFY_TOKEN", "test_token"):
            response = client.get(
                "/webhook",
                params={
                    "hub.mode": "subscribe",
                    "hub.verify_token": "test_token",
                    "hub.challenge": "challenge_123"
                }
            )

        assert response.status_code == 200
        assert response.text == "challenge_123"

    def test_verificacao_token_invalido(self):
        """Should reject invalid verify token."""
        from bot.main import app

        client = TestClient(app)

        with patch("bot.main.WEBHOOK_VERIFY_TOKEN", "test_token"):
            response = client.get(
                "/webhook",
                params={
                    "hub.mode": "subscribe",
                    "hub.verify_token": "wrong_token",
                    "hub.challenge": "challenge_123"
                }
            )

        assert response.status_code == 403


class TestWebhookMessages:
    """Tests for message receiving (POST /webhook)."""

    def _generate_signature(self, payload: bytes, secret: str) -> str:
        """Generate Meta webhook signature."""
        signature = hmac.new(
            secret.encode(),
            payload,
            hashlib.sha256
        ).hexdigest()
        return f"sha256={signature}"

    def test_recebe_mensagem_texto(self, webhook_message_payload):
        """Should receive and process text message."""
        from bot.main import app
        import json

        client = TestClient(app)
        payload = json.dumps(webhook_message_payload).encode()
        signature = self._generate_signature(payload, "test_secret")

        with patch("bot.main.META_APP_SECRET", "test_secret"):
            with patch("bot.main.processar_mensagem", new_callable=AsyncMock) as mock_proc:
                mock_proc.return_value = None

                response = client.post(
                    "/webhook",
                    content=payload,
                    headers={
                        "Content-Type": "application/json",
                        "X-Hub-Signature-256": signature
                    }
                )

        assert response.status_code == 200
        mock_proc.assert_called_once()

    def test_rejeita_assinatura_invalida(self, webhook_message_payload):
        """Should reject invalid signature."""
        from bot.main import app
        import json

        client = TestClient(app)
        payload = json.dumps(webhook_message_payload).encode()

        with patch("bot.main.META_APP_SECRET", "test_secret"):
            response = client.post(
                "/webhook",
                content=payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Hub-Signature-256": "sha256=invalid_signature"
                }
            )

        assert response.status_code == 401

    def test_ignora_status_updates(self):
        """Should ignore status update messages."""
        from bot.main import app
        import json

        status_payload = {
            "object": "whatsapp_business_account",
            "entry": [{
                "changes": [{
                    "value": {
                        "statuses": [{
                            "id": "wamid.123",
                            "status": "delivered"
                        }]
                    },
                    "field": "messages"
                }]
            }]
        }

        client = TestClient(app)
        payload = json.dumps(status_payload).encode()
        signature = self._generate_signature(payload, "test_secret")

        with patch("bot.main.META_APP_SECRET", "test_secret"):
            with patch("bot.main.processar_mensagem", new_callable=AsyncMock) as mock_proc:
                response = client.post(
                    "/webhook",
                    content=payload,
                    headers={
                        "Content-Type": "application/json",
                        "X-Hub-Signature-256": signature
                    }
                )

        assert response.status_code == 200
        mock_proc.assert_not_called()


class TestHealthCheck:
    """Tests for health check endpoint."""

    def test_health_check(self):
        """Should return healthy status."""
        from bot.main import app

        client = TestClient(app)
        response = client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "jobs" in data
