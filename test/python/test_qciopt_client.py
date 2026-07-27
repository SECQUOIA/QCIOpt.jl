from __future__ import annotations

import importlib.util
import os
from collections import deque
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

_REPOSITORY_ROOT = Path(__file__).parents[2]
_MODULE_PATH = Path(
    os.environ.get(
        "QCIOPT_CLIENT_MODULE",
        _REPOSITORY_ROOT / "python" / "qciopt_client.py",
    )
)
_MODULE_SPEC = importlib.util.spec_from_file_location("qciopt_client", _MODULE_PATH)
assert _MODULE_SPEC is not None
assert _MODULE_SPEC.loader is not None
qciopt_client = importlib.util.module_from_spec(_MODULE_SPEC)
_MODULE_SPEC.loader.exec_module(qciopt_client)


class FakeResponse:
    def __init__(self, payload: dict[str, Any], *, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code
        self.text = ""

    def json(self) -> dict[str, Any]:
        return deepcopy(self._payload)

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise qciopt_client.requests.HTTPError(str(self.status_code))


class FakeSession:
    def __init__(self, routes: dict[str, list[FakeResponse]]):
        self._routes = {url: deque(responses) for url, responses in routes.items()}
        self.get_urls: list[str] = []

    def get(self, url: str, **_: Any) -> FakeResponse:
        self.get_urls.append(url)
        return self._routes[url].popleft()


def client_with_session(session: FakeSession):
    client = qciopt_client.OptimizationClient.__new__(qciopt_client.OptimizationClient)
    client._auth_client = SimpleNamespace(
        url="https://api.example.test/",
        timeout=3,
        headers_without_connection_close={},
    )
    client._session = session
    return client


def test_get_job_results_assembles_multipart_results_in_order() -> None:
    jobs_url = "https://api.example.test/optimization/v1/jobs"
    files_url = "https://api.example.test/optimization/v1/files"
    job_id = "job-123"
    file_id = "result-456"
    job_info = {
        "job_id": job_id,
        "job_result": {"file_id": file_id},
    }
    session = FakeSession(
        {
            f"{jobs_url}/{job_id}": [FakeResponse(job_info)],
            f"{jobs_url}/{job_id}/status": [FakeResponse({"status": "COMPLETED"})],
            f"{files_url}/{file_id}": [
                FakeResponse(
                    {
                        "num_parts": 2,
                        "last_accessed_rfc3339": "2026-07-27T00:00:00Z",
                        "upload_date_rfc3339": "2026-07-27T00:00:00Z",
                        "file_config": {
                            "sample": {
                                "num_variables": 2,
                                "solutions": [],
                                "energies": [],
                                "counts": [],
                            }
                        },
                    }
                )
            ],
            f"{files_url}/{file_id}/contents/1": [
                FakeResponse(
                    {
                        "file_config": {
                            "sample": {
                                "solutions": [[1, 0]],
                                "energies": [-2.0],
                                "counts": [3],
                            }
                        }
                    }
                )
            ],
            f"{files_url}/{file_id}/contents/2": [
                FakeResponse(
                    {
                        "file_config": {
                            "sample": {
                                "solutions": [[0, 1]],
                                "energies": [-1.0],
                                "counts": [1],
                            }
                        }
                    }
                )
            ],
        }
    )

    result = client_with_session(session).get_job_results(job_id=job_id)

    assert result == {
        "job_info": job_info,
        "status": "COMPLETED",
        "results": {
            "num_variables": 2,
            "solutions": [[1, 0], [0, 1]],
            "energies": [-2.0, -1.0],
            "counts": [3, 1],
        },
    }
    assert session.get_urls == [
        f"{jobs_url}/{job_id}",
        f"{jobs_url}/{job_id}/status",
        f"{files_url}/{file_id}",
        f"{files_url}/{file_id}/contents/1",
        f"{files_url}/{file_id}/contents/2",
    ]


@pytest.mark.parametrize(
    ("v2_status", "v2_payload"),
    [
        pytest.param(404, {"message": "Not Found"}, id="missing-v2-endpoint"),
        pytest.param(200, {"job_metrics": None}, id="missing-v2-metrics"),
    ],
)
def test_get_job_metrics_falls_back_to_legacy_endpoint(
    v2_status: int,
    v2_payload: dict[str, Any],
) -> None:
    job_url = "https://api.example.test/optimization/v1/jobs/job-123"
    expected = {"job_metrics": {"time_ns": {"wall": {"start": 1, "end": 2}}}}
    session = FakeSession(
        {
            f"{job_url}/metrics/v2": [FakeResponse(v2_payload, status_code=v2_status)],
            f"{job_url}/metrics": [FakeResponse(expected)],
        }
    )

    result = client_with_session(session).get_job_metrics(job_id="job-123")

    assert result == expected
    assert session.get_urls == [
        f"{job_url}/metrics/v2",
        f"{job_url}/metrics",
    ]


@pytest.mark.parametrize("keyword", ["compress", "max_workers"])
def test_client_rejects_unsupported_constructor_keywords(keyword: str) -> None:
    with pytest.raises(TypeError, match=keyword):
        qciopt_client.OptimizationClient(
            url="https://api.example.test",
            api_token="offline-token",
            **{keyword: True},
        )


def test_job_body_rejects_unsupported_file_keywords() -> None:
    client = client_with_session(FakeSession({}))

    with pytest.raises(TypeError, match="graph_file_id"):
        client.build_job_body(
            job_type="sample-qubo",
            job_params={"device_type": "dirac-1"},
            qubo_file_id="qubo-file",
            graph_file_id="graph-file",
        )
