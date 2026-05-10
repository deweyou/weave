from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_returns_service_status() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "weave-agent",
        "version": "0.1.0",
    }


def test_echo_returns_message() -> None:
    response = client.post("/echo", json={"message": "hello weave"})

    assert response.status_code == 200
    assert response.json() == {"message": "hello weave", "received": True}


def test_discover_returns_mock_writing_questions() -> None:
    response = client.post(
        "/writing/discover",
        json={"input": "我想写一篇关于 agent 产品为什么不能只是聊天壳的文章"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["stage"] == "discover"
    assert "agent 产品" in body["summary"]
    assert body["questions"] == [
        "你这篇最想写给谁看？",
        "你最想强调的一条判断是什么？",
        "你有没有真实经历让你形成这个判断？",
    ]


def test_discover_rejects_empty_input() -> None:
    response = client.post("/writing/discover", json={"input": "   "})

    assert response.status_code == 422
