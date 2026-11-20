import pytest

from app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.get_json()["message"] == "Hello from jenkins-pipeline"


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_version_defaults(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    monkeypatch.delenv("GIT_SHA", raising=False)
    assert client.get("/version").get_json() == {"version": "dev", "git_sha": "unknown"}


def test_version_from_env(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("GIT_SHA", "abc1234")
    assert client.get("/version").get_json() == {"version": "1.2.3", "git_sha": "abc1234"}


@pytest.mark.parametrize(("a", "b", "expected"), [("2", "3", 5.0), ("-1", "1.5", 0.5)])
def test_add(client, a, b, expected):
    resp = client.get(f"/add?a={a}&b={b}")
    assert resp.status_code == 200
    assert resp.get_json() == {"result": expected}


@pytest.mark.parametrize("query", ["", "?a=1", "?a=x&b=2"])
def test_add_bad_input(client, query):
    assert client.get(f"/add{query}").status_code == 400


@pytest.mark.parametrize(("a", "b", "expected"), [("2", "3", 5.0), ("-2", "1.5", -3.0)])
def test_multiply(client, a, b, expected):
    resp = client.get(f"/multiply?a={a}&b={b}")
    assert resp.status_code == 200
    assert resp.get_json() == {"result": expected}


@pytest.mark.parametrize("query", ["", "?b=1", "?a=1&b=y"])
def test_multiply_bad_input(client, query):
    assert client.get(f"/multiply{query}").status_code == 400
